# shellcheck shell=bash
# The plugin's example .claude/reviewers.toml and this repository's own one use only version 2 keys and safe
# values, and their [[expect]] cases hold when routed with the git commands review-changes documents
# ("Routing with git" and add-reviewer's "The check": a throwaway index, then git ls-files per route).
# Repo-only test: it may use python3 (tomllib); the plugin ships no code.
set -euo pipefail
source tests/lib.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT

check_config() {
  python3 - "$1" "$temporary_directory" <<'PY'
import re, subprocess, sys, tomllib, os
config_path, scratch = sys.argv[1], sys.argv[2]
config = tomllib.load(open(config_path, "rb"))
problems = []
top = {"version", "default_reviewer", "default_model", "allow_default", "routes", "changed_lines", "model_rules", "expect"}
tables = {
    "routes": {"paths", "reviewers", "reason"},
    "changed_lines": {"paths", "line_regex", "ignore_case", "reviewers", "reason"},
    "model_rules": {"reviewer", "model", "commit_regex", "paths", "min_added_lines", "reason"},
    "expect": {"path", "reviewers"},
    "allow_default": {"paths", "reason"},
}
if config.get("version") != 2:
    problems.append("version is not 2")
problems += [f"unknown top-level key {key}" for key in config if key not in top]
for table, allowed in tables.items():
    for entry in config.get(table, []):
        problems += [f"{table}: unknown key {key}" for key in entry if key not in allowed]

def unsafe(value):
    return "'" in value or "\n" in value or "\r" in value or "\0" in value or value.startswith("-") \
        or (value.startswith(":") and not value.startswith(":!"))

for table in ("routes", "changed_lines", "model_rules", "allow_default"):
    for entry in config.get(table, []):
        for value in entry.get("paths", []) + [entry[k] for k in ("line_regex", "commit_regex") if k in entry]:
            if unsafe(value):
                problems.append(f"{table}: unsafe value {value!r}")
reviewer_name = re.compile(r"^[A-Za-z0-9_-]+(:[A-Za-z0-9_-]+)?$")
names = [config.get("default_reviewer", "review-routing:change-reviewer")]
for table in ("routes", "changed_lines", "expect"):
    for entry in config.get(table, []):
        names += entry["reviewers"]
names += [rule["reviewer"] for rule in config.get("model_rules", [])]
for name in names:
    if name == "general-purpose" or not reviewer_name.match(name):
        problems.append(f"reviewer {name!r} is not allowed")
models = [config["default_model"]] if "default_model" in config else []
models += [rule["model"] for rule in config.get("model_rules", [])]
problems += [f"model {m!r} is not sonnet, opus or fable" for m in models if m not in ("sonnet", "opus", "fable")]

# The documented check: expect paths in a throwaway index, then git ls-files per route.
default = config.get("default_reviewer", "review-routing:change-reviewer")
expects = config.get("expect", [])
index = os.path.join(scratch, os.path.basename(config_path) + ".index")
blob = subprocess.run(["git", "hash-object", "-t", "blob", "/dev/null"], capture_output=True, text=True, check=True).stdout.strip()
lines = "".join(f"100644 {blob}\t{e['path']}\n" for e in expects)
environment = dict(os.environ, GIT_INDEX_FILE=index)
subprocess.run(["git", "update-index", "--index-info"], input=lines, text=True, env=environment, check=True)
got = {e["path"]: set() for e in expects}
for route in config.get("routes", []):
    claimed = subprocess.run(["git", "--glob-pathspecs", "ls-files", "--", *route["paths"]],
                             capture_output=True, text=True, env=environment, check=True).stdout.split("\n")
    for path in claimed:
        if path in got:
            got[path] |= set(route["reviewers"])
for e in expects:
    actual = got[e["path"]] or {default}
    if actual != set(e["reviewers"]):
        problems.append(f"expect {e['path']}: got {sorted(actual)}, expected {sorted(e['reviewers'])}")
print("\n".join(problems))
PY
}

# The check catches a broken config.
cat > "$temporary_directory/broken.toml" <<'TOML'
version = 2
default_model = "haiku"
[[routes]]
paths = [":/", "src'; touch x #"]
reviewers = ["general-purpose"]
pattern = '^src/'
[[expect]]
path = "src/a.py"
reviewers = ["payments-reviewer"]
TOML
problems=$(check_config "$temporary_directory/broken.toml")
assert_contains "$problems" "unsafe value ':/'"
assert_contains "$problems" "unsafe value \"src'; touch x #\""
assert_contains "$problems" "reviewer 'general-purpose' is not allowed"
assert_contains "$problems" "model 'haiku'"
assert_contains "$problems" "routes: unknown key pattern"
assert_contains "$problems" "expect src/a.py"
printf 'pattern = "x"\n' > "$temporary_directory/old.toml"
assert_contains "$(check_config "$temporary_directory/old.toml")" "version is not 2"

# The shipped example and this repository's config pass, expectations included.
assert_eq "$(check_config plugins/review-routing/skills/add-reviewer/reviewers.example.toml)" ""
assert_eq "$(check_config .claude/reviewers.toml)" ""
