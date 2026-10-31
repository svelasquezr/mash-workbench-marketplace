# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
script="$PWD/plugins/review-routing/skills/review-pr/reviewers-for-change.py"
skill_directory="$PWD/plugins/review-routing/skills"
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
isolate_git_config

route() { python3 "$script" "$@"; }

# A fake `gh` for --pr: `gh api ...` logs its arguments, prints $fake_gh_directory/pr_files.json (the
# files listing) or $fake_gh_directory/pr.json (the pull request itself) and exits with
# $fake_gh_directory/api_exit (default 0).
fake_gh_directory="$temporary_directory/fake-gh"
mkdir -p "$fake_gh_directory/bin"
cat > "$fake_gh_directory/bin/gh" <<'EOF'
#!/usr/bin/env bash
state_directory="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >> "$state_directory/calls"
[[ "$1" == api ]] || { echo "fake gh: unexpected call: $*" >&2; exit 99; }
api_exit=$(cat "$state_directory/api_exit" 2>/dev/null || echo 0)
(( api_exit == 0 )) || { echo "fake gh: HTTP 404" >&2; exit "$api_exit"; }
if [[ "$*" == */files ]]; then cat "$state_directory/pr_files.json"; else cat "$state_directory/pr.json"; fi
EOF
chmod +x "$fake_gh_directory/bin/gh"
pr_files() { rm -f "$fake_gh_directory/calls" "$fake_gh_directory/api_exit"; printf '%s' "$1" > "$fake_gh_directory/pr_files.json"; }

write_config() {
  mkdir -p "$repository/.claude"
  cat > "$repository/.claude/reviewers.toml"
}

# new_repository <name>: a project with three specialist agents, a routing config and one commit.
new_repository() {
  repository="$temporary_directory/$1"
  mkdir -p "$repository"
  git -C "$repository" init --quiet
  for file_path in src/billing/charge.py src/core/money.py src/ui/page.js docs/guide.md README.md \
      tests/core/test_money_rounding.py; do
    mkdir -p "$repository/$(dirname "$file_path")"
    echo "# $file_path" > "$repository/$file_path"
  done
  printf '[project]\ndependencies = [\n  "payments-sdk==1.0",\n  "colors==2.0",\n]\n' > "$repository/pyproject.toml"
  mkdir -p "$repository/.claude/agents"
  for agent in billing-reviewer security-reviewer docs-reviewer tooling-reviewer; do
    printf -- '---\nname: %s\ndescription: Reviews things\ntools: Read, Grep, Glob, Bash\n---\n' "$agent" \
      > "$repository/.claude/agents/$agent.md"
  done
  write_config <<'EOF'
allow_default = ['^src/ui/', '^pyproject\.toml$']

[[routes]]
pattern = '^src/billing/'
reviewers = ["billing-reviewer"]

[[routes]]  # money is billing's and security's
pattern = '^src/core/money\.py$'
reviewers = ["billing-reviewer", "security-reviewer"]

[[routes]]
pattern = '^docs/'
reviewers = ["docs-reviewer"]

[[routes]]
pattern = '^\.claude/'
reviewers = ["tooling-reviewer"]

[[mirrors]]
pattern = '^tests/(?P<folders>(?:[^/]+/)*)test_(?P<name>[^/]+)$'
source = 'src/\g<folders>\g<name>'
shorter_names = true

[[changed_lines]]
path_pattern = '^pyproject\.toml$'
line_pattern = 'payments[-_]sdk'
reviewers = ["billing-reviewer"]

[[fallbacks]]
pattern = '\.md$'
reviewers = ["docs-reviewer"]

[[expect]]
path = "src/billing/refund.py"
reviewers = ["billing-reviewer"]

[[expect]]
path = "tests/core/test_money_rounding.py"
reviewers = ["billing-reviewer", "security-reviewer"]

[[expect]]
path = "src/ui/page.js"
reviewers = ["review-routing:change-reviewer"]
EOF
  git -C "$repository" add -A
  git -C "$repository" commit --quiet -m "chore: base"
  base=$(git -C "$repository" rev-parse HEAD)
  cd "$repository"
}

# change <file> [content]: writes and commits one file.
change() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${2:-changed $1}" > "$1"
  git add -A
  git commit --quiet -m "feat: change $1"
}

# --- Usage (exit 2) -------------------------------------------------------------------------------
new_repository usage
run_capturing route
assert_eq "$captured_exit_code" "2"
run_capturing route HEAD
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "not a range"
run_capturing route "$base...HEAD" --pr 3
assert_eq "$captured_exit_code" "2"
run_capturing route --help
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" ".claude/reviewers.toml"
assert_contains "$captured_output" "exit codes"

# Python older than 3.11 gets the clean message and exit 1, never a traceback. The route_* modules need
# 3.10+, so the guard must run before any of them is imported: the stub tomllib fails loudly when a
# route_* module is already loaded, and otherwise stands in for a Python without tomllib.
mkdir -p "$temporary_directory/no-tomllib"
cat > "$temporary_directory/no-tomllib/tomllib.py" <<'EOF2'
import sys

loaded = sorted(name for name in sys.modules if name.startswith("route_"))
if loaded:
    raise SystemExit(f"route modules imported before the guard: {loaded}")
raise ModuleNotFoundError("tomllib")
EOF2
PYTHONPATH="$temporary_directory/no-tomllib" run_capturing route --help
assert_eq "$captured_exit_code" "1"
assert_eq "$captured_output" "reviewers-for-change: needs Python 3.11 or newer (tomllib)"
# The real thing, where an old interpreter is installed.
for old_python in python3.9 python3.10; do
  if command -v "$old_python" > /dev/null; then
    run_capturing "$old_python" "$script" --help
    assert_eq "$captured_exit_code" "1"
    assert_eq "$captured_output" "reviewers-for-change: needs Python 3.11 or newer (tomllib)"
  fi
done

# --- Routing a branch (<base>...<head>) ------------------------------------------------------------
new_repository branch
git checkout --quiet -b feature
change src/billing/charge.py
run_capturing route "$base...feature"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "billing-reviewer"

# A path matched by a route that names two reviewers gets both; a mixed change lists each reviewer once,
# sorted; a path no route claims falls back (Markdown to docs-reviewer, anything else to review-routing:change-reviewer).
change src/core/money.py
change README.md
change src/ui/page.js
change docs/guide.md
run_capturing route "$base...feature"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "$(printf 'billing-reviewer\ndocs-reviewer\nreview-routing:change-reviewer\nsecurity-reviewer')"

# Three dots: only the branch's own changes, even after the base moved on.
git checkout --quiet -
change .claude/settings.json "{}"
git checkout --quiet feature
run_capturing route "$base...feature"
assert_not_contains "$captured_output" "tooling-reviewer"

# Two dots between two heads (a fix round): only what the fix touched.
fix_base=$(git rev-parse HEAD)
change src/billing/charge.py "fixed"
run_capturing route "$fix_base..HEAD"
assert_eq "$captured_output" "billing-reviewer"

# A deleted file still needs its reviewer; a rename counts its old and its new path.
new_repository delete-and-rename
git rm --quiet src/billing/charge.py
git commit --quiet -m "refactor: drop charge"
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "billing-reviewer"
new_repository rename
git mv src/billing/charge.py src/ui/charge.py
git commit --quiet -m "refactor: move charge"
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"

# A test counts as the code it mirrors, including a shorter name (test_money_rounding -> money.py);
# without shorter_names it does not.
new_repository mirror
change tests/core/test_money_rounding.py
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nsecurity-reviewer')"
gnu_sed -i 's/^shorter_names = true$/shorter_names = false/' .claude/reviewers.toml
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "review-routing:change-reviewer"

# The default reviewer can be renamed.
new_repository default-reviewer
gnu_sed -i '1i default_reviewer = "careful-reviewer"' .claude/reviewers.toml
git commit --quiet -am "chore: rename the default reviewer"; base=$(git rev-parse HEAD)
change src/ui/page.js
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "careful-reviewer"

# A project that kept the old default (the built-in general-purpose agent) still routes and checks.
new_repository old-default
gnu_sed -i '1i default_reviewer = "general-purpose"' .claude/reviewers.toml
gnu_sed -i 's/^reviewers = \["review-routing:change-reviewer"\]$/reviewers = ["general-purpose"]/' .claude/reviewers.toml
git commit --quiet -am "chore: keep the old default reviewer"; base=$(git rev-parse HEAD)
change src/ui/page.js
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "general-purpose"
run_capturing route --check
assert_eq "$captured_exit_code" "0"

# A changed line in a matching file adds reviewers; another dependency's line does not; a colored git
# config does not hide it.
new_repository changed-lines
change pyproject.toml "$(printf '[project]\ndependencies = [\n  "payments-sdk==1.1",\n  "colors==2.0",\n]')"
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
git config color.ui always
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
new_repository other-dependency
change pyproject.toml "$(printf '[project]\ndependencies = [\n  "payments-sdk==1.0",\n  "colors==2.1",\n]')"
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "review-routing:change-reviewer"

# A lone \r inside a changed line is content, not a line end: the text after it is still that line.
new_repository lone-cr
change pyproject.toml "$(printf '[project]\ndependencies = [\n  "payments-sdk==1.0",\n  "colors==2.1\rpayments-sdk==1.1",\n]')"
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"

# A lone \r inside a commit subject is content, not a subject end: a rule anchored on "^b" must not match
# the text after it.
new_repository subject-cr
printf -- '---\nname: billing-reviewer\nmodel: opus\n---\n' > .claude/agents/billing-reviewer.md
cat >> .claude/reviewers.toml <<'EOF'

[[model_rules]]
reviewer = "billing-reviewer"
model = "fable"
title_pattern = '^b'
reason = "subject starts with b"
EOF
git add -A; git commit --quiet -m "chore: rule"; base=$(git rev-parse HEAD)
printf 'x\n' > src/billing/charge.py; git add -A; git commit --quiet -m "$(printf 'feat: a\rb')"
run_capturing route "$base...HEAD" --models
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "billing-reviewer	-"

# --paths routes paths without git history.
new_repository paths
run_capturing route --paths src/core/money.py notes.md
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "$(printf 'billing-reviewer\ndocs-reviewer\nsecurity-reviewer')"

# --- Errors are never "no reviewers" (exit 1) -------------------------------------------------------
new_repository empty
run_capturing route "$base...HEAD"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no changed files"
run_capturing route "$base...no-such-branch"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "could not read"

# --- Config errors (exit 1) -------------------------------------------------------------------------
new_repository config-errors
change src/billing/charge.py
rm .claude/reviewers.toml
# No config file and no --config: not an error. Every path gets the default reviewer on its own model, with a note.
run_capturing route "$base...HEAD"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "review-routing:change-reviewer"
assert_contains "$captured_output" ".claude/reviewers.toml"
assert_contains "$captured_output" "add-reviewer"
assert_contains "$captured_output" "update this checkout"
assert_not_contains "$captured_output" "Traceback"
assert_eq "$(route "$base...HEAD" 2>/dev/null)" "review-routing:change-reviewer"
assert_eq "$(route "$base...HEAD" --models 2>/dev/null)" "review-routing:change-reviewer	-"
assert_eq "$(route --paths src/billing/charge.py docs/guide.md 2>/dev/null)" "review-routing:change-reviewer"
run_capturing route "$base...HEAD" --explain --format markdown
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "Review routing"
# The note goes to stderr only, once.
assert_eq "$(route "$base...HEAD" 2>&1 >/dev/null | grep -c 'add-reviewer')" "1"
# An empty change is still an error without a config.
run_capturing route "HEAD...HEAD"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no changed files"
# A config path that exists but is no file (a directory) is an error, not "no routing yet".
mkdir .claude/reviewers.toml
run_capturing route "$base...HEAD"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no routing config"
rmdir .claude/reviewers.toml
# --check and an explicit --config stay strict.
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no routing config"
run_capturing route "$base...HEAD" --config "$repository/.claude/missing.toml"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no routing config"

expect_config_error() {
  run_capturing route "$base...HEAD"
  assert_eq "$captured_exit_code" "1"
  assert_contains "$captured_output" "$1"
  assert_not_contains "$captured_output" "Traceback"
}
printf '[[routes]\npattern = 1\n' | write_config
expect_config_error "not valid TOML"
printf '[[routes]]\npattern = "^src/"\n' | write_config
expect_config_error "routes[1]: missing key 'reviewers'"
printf '[[routes]]\npattern = "^src/"\nreviewer = "a"\nreviewers = ["a"]\n' | write_config
expect_config_error "routes[1]: unknown key 'reviewer'"
printf '[[routes]]\npattern = "^src/("\nreviewers = ["a"]\n' | write_config
expect_config_error "routes[1].pattern"
printf '[[routes]]\npattern = "^src/"\nreviewers = "a"\n' | write_config
expect_config_error "routes[1].reviewers"
printf '[[routes]]\npattern = "^src/"\nreviewers = []\n' | write_config
expect_config_error "routes[1].reviewers"
printf 'route = []\n' | write_config
expect_config_error "unknown key 'route'"
printf '[[mirrors]]\npattern = "^tests/(.*)$"\nsource = "src/\\\\g<missing>"\n[[expect]]\npath = "tests/x"\nreviewers = ["a"]\n' \
  | write_config
expect_config_error "mirrors[1]"
# --config points elsewhere.
mkdir -p "$temporary_directory/elsewhere"
printf '[[routes]]\npattern = "^src/billing/"\nreviewers = ["outside-reviewer"]\n' > "$temporary_directory/elsewhere/routes.toml"
run_capturing route --config "$temporary_directory/elsewhere/routes.toml" "$base...HEAD"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "outside-reviewer"

# --- Pull requests (--pr) ---------------------------------------------------------------------------
new_repository pull-request
export PATH="$fake_gh_directory/bin:$PATH"
# Every page is read, and a rename's previous path counts (moving code out of billing keeps its reviewer).
pr_files '[[{"filename": "src/ui/charge.py", "previous_filename": "src/billing/charge.py"}], [{"filename": "docs/guide.md"}]]'
run_capturing route --pr 7
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "$(printf 'billing-reviewer\ndocs-reviewer\nreview-routing:change-reviewer')"
assert_contains "$(cat "$fake_gh_directory/calls")" "api --paginate --slurp repos/{owner}/{repo}/pulls/7/files"
# A matching changed line in the patch adds reviewers; a missing patch (GitHub omits large ones) errs
# towards more review; another line does not.
pr_files '[[{"filename": "pyproject.toml", "patch": "@@ -1 +1 @@\n-\"payments-sdk==1.0\"\n+\"payments-sdk==1.1\""}]]'
run_capturing route --pr 7
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
pr_files '[[{"filename": "pyproject.toml"}]]'
run_capturing route --pr 7
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
pr_files '[[{"filename": "pyproject.toml", "patch": "@@ -1 +1 @@\n-\"colors==2.0\"\n+\"colors==2.1\"\n payments-sdk context"}]]'
run_capturing route --pr 7
assert_eq "$captured_output" "review-routing:change-reviewer"
# An anchored pattern sees the line without its +/- prefix.
gnu_sed -i "s|^line_pattern = .*|line_pattern = '^\"payments'|" .claude/reviewers.toml
pr_files '[[{"filename": "pyproject.toml", "patch": "@@ -1 +1 @@\n-\"payments-sdk==1.0\"\n+\"payments-sdk==1.1\""}]]'
run_capturing route --pr 7
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
# A blank line in a patch is context, not a changed line (even for a pattern that matches empty text).
gnu_sed -i "s|^line_pattern = .*|line_pattern = '^\$'|" .claude/reviewers.toml
pr_files '[[{"filename": "pyproject.toml", "patch": "@@ -1,3 +1,3 @@\n context\n\n context"}]]'
run_capturing route --pr 7
assert_eq "$captured_output" "review-routing:change-reviewer"
# Errors: gh fails, no files, not JSON, the wrong shape, gh missing.
pr_files '[]'
echo 1 > "$fake_gh_directory/api_exit"
run_capturing route --pr 7
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "HTTP 404"
pr_files '[[]]'
run_capturing route --pr 7
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "no changed files"
pr_files 'not json'
run_capturing route --pr 7
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "JSON"
pr_files '[{"filename": "a"}]'
run_capturing route --pr 7
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "unexpected"
mkdir -p "$temporary_directory/no-gh"
ln -sf "$(command -v git)" "$temporary_directory/no-gh/git"
python_path=$(command -v python3)
PATH="$temporary_directory/no-gh" run_capturing "$python_path" "$script" --pr 7
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "gh is not installed"

# --- --check: the config's own tests ----------------------------------------------------------------
new_repository check
run_capturing route --check
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "ok"
# A wrong expectation names the path, what it got and what was expected.
cat >> .claude/reviewers.toml <<'EOF'

[[expect]]
path = "src/billing/refund.py"
reviewers = ["docs-reviewer"]
EOF
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "src/billing/refund.py"
assert_contains "$captured_output" "expected docs-reviewer"
assert_contains "$captured_output" "got billing-reviewer"
# A tracked path that falls back to the default reviewer and is not in allow_default.
new_repository check-coverage
change src/reports/summary.py
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "src/reports/summary.py"
assert_contains "$captured_output" "allow_default"
# A stale allow_default entry, a stale route and a reviewer without an agent file.
new_repository check-stale
gnu_sed -i "1s|.*|allow_default = ['^src/ui/', '^pyproject\\\\.toml\$', '^gone/']|" .claude/reviewers.toml
cat >> .claude/reviewers.toml <<'EOF'

[[routes]]
pattern = '^src/legacy/'
reviewers = ["legacy-reviewer"]
EOF
git commit --quiet -am "chore: routes"
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "'^gone/'"
assert_contains "$captured_output" "'^src/legacy/' matches no tracked file"
assert_contains "$captured_output" "legacy-reviewer"
assert_contains "$captured_output" ".claude/agents"
# Without allow_default, coverage is not checked and says so; plugin agents (with a colon) need no file.
new_repository check-no-coverage
gnu_sed -i '1d' .claude/reviewers.toml
cat >> .claude/reviewers.toml <<'EOF'

[[routes]]
pattern = '^README\.md$'
reviewers = ["some-plugin:readme-reviewer"]
EOF
run_capturing route --check
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "coverage not checked"

# --- --explain: which rule gave each path its reviewers ---------------------------------------------
new_repository explain
write_config <<'EOF'
allow_default = [
  { pattern = '^src/ui/', reason = "display only" },
  '^pyproject\.toml$',
  { pattern = '^\.claude/', reason = "Claude settings" },
]

[[routes]]
pattern = '^src/billing/'
reviewers = ["billing-reviewer"]
reason = "moves money"

[[routes]]
pattern = '^src/core/money\.py$'
reviewers = ["billing-reviewer", "security-reviewer"]

[[routes]]
pattern = '^(docs|notes)/'
reviewers = ["docs-reviewer"]

[[mirrors]]
pattern = '^tests/(?P<folders>(?:[^/]+/)*)test_(?P<name>[^/]+)$'
source = 'src/\g<folders>\g<name>'
shorter_names = true

[[changed_lines]]
path_pattern = '^pyproject\.toml$'
line_pattern = 'payments[-_]sdk'
reviewers = ["billing-reviewer"]
reason = "the SDK moves money"

[[fallbacks]]
pattern = '\.md$'
reviewers = ["docs-reviewer"]
reason = "prose"
EOF
git add -A; git commit --quiet -m "chore: routes with reasons"; base=$(git rev-parse HEAD)
change src/billing/charge.py
change tests/core/test_money_rounding.py
change README.md
change src/ui/page.js
change pyproject.toml "$(printf '[project]\ndependencies = [\n  "payments-sdk==1.1",\n]')"
run_capturing route "$base...HEAD" --explain
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "src/billing/charge.py"
assert_contains "$captured_output" "route #1 '^src/billing/' — moves money"
assert_contains "$captured_output" "mirror of src/core/money.py: route #2 '^src/core/money\\.py\$'"
assert_contains "$captured_output" "fallback '\\.md\$' — prose"
assert_contains "$captured_output" "default (allow_default '^src/ui/' — display only)"
assert_contains "$captured_output" "default (allow_default '^pyproject\\.toml\$')"
assert_contains "$captured_output" "changed line in pyproject.toml matching 'payments[-_]sdk' — the SDK moves money"
assert_eq "$(tail -n 1 <<< "$captured_output")" \
  "reviewers: billing-reviewer, docs-reviewer, review-routing:change-reviewer, security-reviewer"
# A test that mirrors two candidate sources of one route lists its reviewer once, with the first reason.
run_capturing route --paths tests/billing/test_charge_refund.py --explain
assert_eq "$(sed '/^models:$/,$d' <<< "$captured_output" | grep -c 'billing-reviewer')" "1"
assert_contains "$captured_output" "mirror of src/billing/charge_refund.py: route #1"
# Without --explain the output is unchanged: the names alone.
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\ndocs-reviewer\nreview-routing:change-reviewer\nsecurity-reviewer')"
# Markdown for a PR comment: one table row per reviewer of a path; a | in a pattern is escaped.
run_capturing route "$base...HEAD" --explain --format markdown
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "| Path | Reviewer | Why |"
assert_contains "$captured_output" "| \`src/billing/charge.py\` | billing-reviewer | route #1 \`^src/billing/\` — moves money |"
assert_contains "$captured_output" "**Reviewers:** billing-reviewer, docs-reviewer, review-routing:change-reviewer, security-reviewer"
run_capturing route --paths docs/guide.md --explain --format markdown
assert_contains "$captured_output" "route #3 \`^(docs\\|notes)/\`"
# The markdown starts with its heading; free text is escaped, a pattern sits in a code span whose fence
# outlasts any backticks inside, newlines become spaces and @ can't ping anyone.
markdown_config="$temporary_directory/markdown.toml"
cat > "$markdown_config" <<'EOF'
[[routes]]
pattern = '^src/billing/'
reviewers = ["billing-reviewer"]
reason = """it's *money*, ~~not~~ ask @payments-team\rfirst
now"""

[[routes]]
pattern = '^(docs|notes)/(?!`)'
reviewers = ["docs-reviewer"]
EOF
run_capturing route --config "$markdown_config" --paths src/billing/charge.py docs/guide.md --explain --format markdown
assert_eq "$(head -n 1 <<< "$captured_output")" "### Review routing"
assert_contains "$captured_output" "route #1 \`^src/billing/\` — it's \\*money\\*, \\~\\~not\\~\\~ ask @"$'​'"payments-team first now |"
assert_contains "$captured_output" "route #2 \`\`^(docs\\|notes)/(?!\`)\`\` |"
run_capturing route --config "$markdown_config" --paths src/billing/charge.py --explain
assert_contains "$captured_output" "route #1 '^src/billing/' — it's *money*, ~~not~~ ask @payments-team first now"
# Reasons and allow_default tables pass --check.
run_capturing route --check
assert_eq "$captured_exit_code" "0"
# A changed-line hit names only the file whose line matched, even when two files match path_pattern;
# a file name with glob characters is read literally (app/[id].toml must not see app/i.toml's diff).
new_repository explain-attribution
write_config <<'EOF'
[[changed_lines]]
path_pattern = '\.toml$'
line_pattern = 'payments[-_]sdk'
reviewers = ["billing-reviewer"]
EOF
mkdir -p app
printf 'a = 1\n' > app/i.toml; printf 'b = 1\n' > 'app/[id].toml'; printf 'c = 1\n' > other.toml
git add -A; git commit --quiet -m "chore: base"; base=$(git rev-parse HEAD)
printf 'payments-sdk = 2\n' > app/i.toml; printf 'b = 2\n' > 'app/[id].toml'; printf 'c = 2\n' > other.toml
git add -A; git commit --quiet -m "feat: bump"
run_capturing route "$base...HEAD" --explain
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "changed line in app/i.toml matching"
assert_not_contains "$captured_output" "changed line in other.toml"
assert_not_contains "$captured_output" "changed line in app/[id].toml"
# A pull request: a patch that matches, a missing patch (said so, not claimed as a matching line), and a
# rename whose previous path is the one path_pattern claims (PATH already holds the fake gh).
pr_files '[[{"filename": "a.toml", "patch": "@@ -1 +1 @@\n-x\n+payments-sdk = 2"}, {"filename": "big.toml"}, {"filename": "notes.txt", "previous_filename": "old.toml", "patch": "@@ -1 +1 @@\n-y\n+payments_sdk = 3"}]]'
run_capturing route --pr 7 --explain
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "changed line in a.toml matching 'payments[-_]sdk'"
assert_contains "$captured_output" "no patch from GitHub for big.toml (large diff); assumed to match 'payments[-_]sdk'"
assert_contains "$captured_output" "changed line in old.toml matching 'payments[-_]sdk'"
cd "$repository"
# --format needs --explain; --explain doesn't combine with --check.
run_capturing route --paths a.py --format markdown
assert_eq "$captured_exit_code" "2"
run_capturing route --check --explain
assert_eq "$captured_exit_code" "2"
# A bad allow_default table or reason is a config error.
printf "allow_default = [{ reason = 'x' }]\n" | write_config
expect_config_error "allow_default[1]: missing key 'pattern'"
printf "allow_default = [{ pattern = '^a', why = 'x' }]\n" | write_config
expect_config_error "allow_default[1]: unknown key 'why'"
printf '[[routes]]\npattern = "^src/"\nreviewers = ["a"]\nreason = 3\n' | write_config
expect_config_error "routes[1].reason"

# --- Models: --models prints each reviewer's model --------------------------------------------------
# Precedence: a matching [[model_rules]] entry, then default_model (the default reviewer only), then the
# model: in the reviewer's agent file. --models prints the model the dispatch must pass, or "-" when the
# agent file decides (its model: applies on its own); --explain shows which model and why.
new_repository models
printf -- '---\nname: billing-reviewer\nmodel: opus\n---\n' > .claude/agents/billing-reviewer.md
gnu_sed -i '1i default_model = "opus"' .claude/reviewers.toml
cat >> .claude/reviewers.toml <<'EOF'

[[model_rules]]
reviewer = "billing-reviewer"
model = "fable"
title_pattern = '^feat'
path_pattern = '^src/billing/'
min_added_lines = 3
reason = "new billing code"
EOF
git add -A; git commit --quiet -m "chore: models"; base=$(git rev-parse HEAD)
printf 'a\nb\nc\nd\n' > src/billing/charge.py; git add -A; git commit --quiet -m "feat: bigger charge"
change src/ui/page.js
run_capturing route "$base...HEAD" --models
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "$(printf 'billing-reviewer\tfable\nreview-routing:change-reviewer\topus')"
# Without --models the output is the names alone.
run_capturing route "$base...HEAD"
assert_eq "$captured_output" "$(printf 'billing-reviewer\nreview-routing:change-reviewer')"
# --explain names each reviewer's model and why.
run_capturing route "$base...HEAD" --explain
assert_contains "$captured_output" "billing-reviewer: fable (model rule #1 — new billing code)"
assert_contains "$captured_output" "review-routing:change-reviewer: opus (default_model)"
run_capturing route "$base...HEAD" --explain --format markdown
assert_contains "$captured_output" "| billing-reviewer | fable | model rule #1 — new billing code |"
# Every condition must hold: a fix, or a feat with too few added lines, leaves the agent file's model.
fix_base=$(git rev-parse HEAD)
printf 'a\nb\nc\nd\ne\nf\ng\n' > src/billing/charge.py; git add -A; git commit --quiet -m "fix: charge"
run_capturing route "$fix_base...HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
run_capturing route "$fix_base...HEAD" --explain
assert_contains "$captured_output" "billing-reviewer: opus (agent file)"
small_base=$(git rev-parse HEAD)
printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > src/billing/charge.py; git add -A; git commit --quiet -m "feat: one more line"
run_capturing route "$small_base...HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
# A fix round (<old>..<new>) sees only the fix's commits, so a feat rule doesn't hold there: the review-pr
# skill keeps each reviewer's first-round model instead of asking again.
run_capturing route "$base..HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\tfable\nreview-routing:change-reviewer\topus')"
run_capturing route "$small_base..HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
# <base>...<head> reads only the head's side: a feat that landed on the base doesn't count.
git checkout --quiet -b side "$small_base"
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\n' > src/billing/charge.py; git add -A; git commit --quiet -m "fix: side"
git checkout --quiet -
run_capturing route "HEAD...side" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
# A binary file adds no lines; a rename counts the new file's lines.
binary_base=$(git rev-parse HEAD)
printf 'PNG\000\001\002\003' > src/billing/logo.png; git add -A; git commit --quiet -m "feat: logo"
run_capturing route "$binary_base...HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
rename_base=$(git rev-parse HEAD)
git mv src/billing/charge.py src/billing/charges.py; git commit --quiet -m "feat: rename charge"
run_capturing route "$rename_base...HEAD" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\tfable')"
# A reviewer whose agent file names no model prints "-" too. --paths has no title and no line counts.
run_capturing route --paths docs/guide.md src/billing/charge.py --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-\ndocs-reviewer\t-')"
run_capturing route --paths src/billing/charge.py --title "feat: x" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
gnu_sed -i '/^min_added_lines = 3$/d' .claude/reviewers.toml
run_capturing route --paths src/billing/charge.py --title "feat: x" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\tfable')"
run_capturing route --paths src/billing/charge.py --title "fix: x" --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
# --title only means something with --models or --explain.
run_capturing route --paths src/billing/charge.py --title "feat: x"
assert_eq "$captured_exit_code" "2"
# A pull request: the title from the PR, the added lines from the files listing.
printf 'min_added_lines = 3\n' >> .claude/reviewers.toml
export PATH="$fake_gh_directory/bin:$PATH"
pr_files '[[{"filename": "src/billing/charge.py", "additions": 5}]]'
printf '{"title": "feat(billing): refunds"}' > "$fake_gh_directory/pr.json"
run_capturing route --pr 7 --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\tfable')"
assert_contains "$(cat "$fake_gh_directory/calls")" "api repos/{owner}/{repo}/pulls/7"
pr_files '[[{"filename": "src/billing/charge.py", "additions": 2}]]'
run_capturing route --pr 7 --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\t-')"
# The plugin's own agent: review-routing:change-reviewer's model comes from the plugin's agent file.
new_repository plugin-agent-model
run_capturing route --paths src/ui/page.js --models
assert_eq "$captured_output" "$(printf 'review-routing:change-reviewer\t-')"
run_capturing route --paths src/ui/page.js --explain
assert_contains "$captured_output" "review-routing:change-reviewer: sonnet (agent file)"

# The first rule that holds wins; --title overrides a range's commit subjects; a PR rename's added lines
# count for the path its rule matches; an unreadable pull request is an error; an agent is found by its
# frontmatter name:, never by a name: line in its body.
new_repository models-more
printf -- '---\nname: money-reviewer\nmodel: opus\n---\n' > .claude/agents/money.md
printf -- '---\ndescription: an example\n---\nExample block:\nname: ghost-reviewer\n' > .claude/agents/other.md
cat >> .claude/reviewers.toml <<'EOF'

[[routes]]
pattern = '^src/core/'
reviewers = ["money-reviewer"]

[[model_rules]]
reviewer = "billing-reviewer"
model = "opus"
path_pattern = '^src/billing/'

[[model_rules]]
reviewer = "billing-reviewer"
model = "fable"
path_pattern = '^src/'

[[model_rules]]
reviewer = "security-reviewer"
model = "fable"
title_pattern = '^feat'
path_pattern = '^src/core/'
min_added_lines = 3
EOF
git add -A; git commit --quiet -m "chore: more models"; base=$(git rev-parse HEAD)
run_capturing route --paths src/billing/charge.py --models
assert_eq "$captured_output" "$(printf 'billing-reviewer\topus')"
printf 'a\nb\nc\nd\n' > src/core/money.py; git add -A; git commit --quiet -m "fix: money"
run_capturing route "$base...HEAD" --models
assert_contains "$captured_output" "$(printf 'security-reviewer\t-')"
run_capturing route "$base...HEAD" --title "feat: money" --models
assert_contains "$captured_output" "$(printf 'security-reviewer\tfable')"
run_capturing route "$base...HEAD" --explain
assert_contains "$captured_output" "money-reviewer: opus (agent file)"
pr_files '[[{"filename": "src/ui/money.py", "previous_filename": "src/core/money.py", "additions": 5}]]'
printf '{"title": "feat: move money"}' > "$fake_gh_directory/pr.json"
run_capturing route --pr 8 --models
assert_contains "$captured_output" "$(printf 'security-reviewer\tfable')"
printf 'not json' > "$fake_gh_directory/pr.json"
run_capturing route --pr 8 --models
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "pull request 8"
assert_not_contains "$captured_output" "Traceback"
cat >> .claude/reviewers.toml <<'EOF'

[[routes]]
pattern = '^README\.md$'
reviewers = ["ghost-reviewer"]
EOF
run_capturing route --check
assert_contains "$captured_output" "reviewer 'ghost-reviewer' has no agent file"

# Model names: sonnet, opus or fable (what the Agent tool's model accepts); never haiku for a reviewer.
new_repository model-errors
change src/billing/charge.py
gnu_sed -i '1i default_model = "gpt-4"' .claude/reviewers.toml
expect_config_error "default_model"
gnu_sed -i '1s/.*/default_model = "haiku"/' .claude/reviewers.toml
expect_config_error "haiku"
gnu_sed -i '1s/.*/default_model = "claude-haiku-4-5"/' .claude/reviewers.toml
expect_config_error "haiku"
gnu_sed -i '1s/.*/default_model = "claude-opus-5-5"/' .claude/reviewers.toml
expect_config_error "sonnet, opus or fable"
gnu_sed -i '1s/.*/default_model = "inherit"/' .claude/reviewers.toml
expect_config_error "sonnet, opus or fable"
gnu_sed -i '1s/.*/default_model = "fable"/' .claude/reviewers.toml
run_capturing route "$base...HEAD" --models
assert_eq "$captured_exit_code" "0"
printf '[[model_rules]]\nreviewer = "a"\nmodel = "Haiku"\n' | write_config
expect_config_error "model_rules[1].model"
printf '[[model_rules]]\nreviewer = "a"\nmodel = "opus"\nmin_added_lines = 3\n' | write_config
expect_config_error "min_added_lines needs path_pattern"
printf '[[model_rules]]\nreviewer = "a"\nmodel = "opus"\npath_pattern = "^a"\nmin_added_lines = 0\n' | write_config
expect_config_error "min_added_lines"
# --check: a routed agent file on haiku (even after a byte-order mark, with a capital Model:), a rule for
# a reviewer nothing routes, a stale path_pattern. --models refuses to dispatch the haiku reviewer.
new_repository check-models
printf -- '\xef\xbb\xbf---\nname: docs-reviewer\nModel: "Haiku"\n---\n' > .claude/agents/docs-reviewer.md
printf -- '---\nname: security-reviewer\nmodel: # to decide\n---\n' > .claude/agents/security-reviewer.md
cat >> .claude/reviewers.toml <<'EOF'

[[model_rules]]
reviewer = "ghost-reviewer"
model = "opus"

[[model_rules]]
reviewer = "billing-reviewer"
model = "opus"
path_pattern = '^src/gone/'
EOF
git add -A; git commit --quiet -m "chore: models"
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "docs-reviewer runs on haiku"
assert_contains "$captured_output" "model_rules[1]: ghost-reviewer is not routed"
assert_contains "$captured_output" "model_rules[2]: '^src/gone/' matches no tracked file"
assert_contains "$captured_output" "security-reviewer's agent file has an empty model:"
run_capturing route --paths docs/guide.md --models
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "haiku"

# --- Import guards: every module a critical entry point imports has the guard's reviewer ------------
# new_guard_repository: app.orders imports app.risk and (relatively) app.helpers; app.risk imports
# app.money, which imports app.sub.deep; app.ui is imported by nobody. Only orders.py and risk.py are
# routed to safety-reviewer.
new_guard_repository() {
  repository="$temporary_directory/$1"
  mkdir -p "$repository/src/app/sub" "$repository/.claude/agents"
  git -C "$repository" init --quiet
  printf '' > "$repository/src/app/__init__.py"
  printf 'from app import risk\nfrom .helpers import fmt\n' > "$repository/src/app/orders.py"
  printf 'import app.money\n' > "$repository/src/app/risk.py"
  printf 'from app.sub.deep import depth\n' > "$repository/src/app/money.py"
  printf 'def fmt():\n    pass\n' > "$repository/src/app/helpers.py"
  printf 'import os\n' > "$repository/src/app/ui.py"
  printf '' > "$repository/src/app/sub/__init__.py"
  printf 'depth = 1\n' > "$repository/src/app/sub/deep.py"
  printf -- '---\nname: safety-reviewer\nmodel: fable\n---\n' > "$repository/.claude/agents/safety-reviewer.md"
  cat > "$repository/.claude/reviewers.toml" <<'EOF'
[[routes]]
pattern = '^src/app/(orders|risk)\.py$'
reviewers = ["safety-reviewer"]

[[import_guards]]
name = "critical path"
language = "python"
source_dirs = ["src"]
entry_modules = ["app.orders"]
reviewer = "safety-reviewer"
allow = [
  { path = "src/app/__init__.py", reason = "package marker" },
  { pattern = '^src/app/sub/', reason = "pure helpers, no orders" },
]
EOF
  git -C "$repository" add -A
  git -C "$repository" commit --quiet -m "chore: base"
  cd "$repository"
}
new_guard_repository guard
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "src/app/money.py"
assert_contains "$captured_output" "app.orders → app.risk → app.money"
assert_contains "$captured_output" "src/app/helpers.py"
assert_not_contains "$captured_output" "src/app/ui.py"
assert_not_contains "$captured_output" "src/app/sub/deep.py"
# Allowing them, with a reason, passes.
gnu_sed -i 's|^  { pattern = .\^src/app/sub/., reason = "pure helpers, no orders" },$|&\n  { path = "src/app/money.py", reason = "amount formatting" },\n  { path = "src/app/helpers.py", reason = "string helpers" },|' .claude/reviewers.toml
git commit --quiet -am "chore: allow"
run_capturing route --check
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "critical path"
# --explain shows that a changed file is on the guarded path, and through which imports.
run_capturing route --paths src/app/money.py --explain
assert_contains "$captured_output" "on import guard 'critical path' via app.orders → app.risk → app.money"
run_capturing route --paths src/app/ui.py --explain
assert_not_contains "$captured_output" "critical path"
# A stale allow entry: a file the path no longer reaches, or one now routed to the reviewer.
gnu_sed -i 's|^  { path = "src/app/helpers.py", reason = "string helpers" },$|&\n  { path = "src/app/ui.py", reason = "not imported" },\n  { path = "src/app/risk.py", reason = "routed anyway" },|' .claude/reviewers.toml
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "src/app/ui.py"
assert_contains "$captured_output" "src/app/risk.py"
assert_contains "$captured_output" "stale"
# A missing entry module, and a file on the path that doesn't parse.
new_guard_repository guard-errors
gnu_sed -i 's|^entry_modules = \["app.orders"\]$|entry_modules = ["app.orders", "app.gone"]|' .claude/reviewers.toml
printf 'def broken(:\n' > src/app/money.py
git add -A; git commit --quiet -m "chore: break"
run_capturing route --check
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "app.gone"
assert_contains "$captured_output" "src/app/money.py"
assert_contains "$captured_output" "parse"
assert_not_contains "$captured_output" "Traceback"
# Resolution follows Python: a package beats a module of the same name; a relative import in an
# __init__.py is relative to that package; .. climbs one package; a relative import past the top
# package is not followed; a coding cookie is honoured; an unreadable file is a problem, not a crash.
new_guard_repository guard-resolution
printf 'import app.pk\nimport app.latin\n' >> src/app/risk.py
printf '' > src/app/pk.py
mkdir -p src/app/pk; printf 'import app.pk_deep\n' > src/app/pk/__init__.py; printf '' > src/app/pk_deep.py
printf 'from . import extra\n' > src/app/sub/__init__.py; printf '' > src/app/sub/extra.py
printf 'from .. import helpers2\nfrom ... import top\n' >> src/app/sub/deep.py
printf '' > src/app/helpers2.py; printf '' > src/top.py
printf '# -*- coding: latin-1 -*-\nname = "caf\xe9"\n' > src/app/latin.py
git add -A; git commit --quiet -m "chore: resolution cases"
run_capturing route --paths src/app/pk/__init__.py src/app/pk_deep.py src/app/sub/extra.py src/top.py --explain
assert_contains "$captured_output" "src/app/pk/__init__.py: on import guard 'critical path' via"
assert_contains "$captured_output" "src/app/pk_deep.py: on import guard 'critical path' via"
assert_contains "$captured_output" "src/app/sub/extra.py: on import guard 'critical path' via"
assert_not_contains "$captured_output" "src/top.py: on import guard"
run_capturing route --check
assert_contains "$captured_output" "src/app/helpers2.py is on the path (via app.orders → app.risk → app.money → app.sub.deep → app.helpers2)"
assert_not_contains "$captured_output" "src/app/pk.py"
assert_not_contains "$captured_output" "could not parse src/app/latin.py"
run_capturing route --paths src/app/money.py --explain --format markdown
assert_contains "$captured_output" "| Path | Import guard | Imported via |"
if [[ "$(id -u)" != 0 ]]; then  # root reads a chmod 000 file anyway
  chmod 000 src/app/helpers2.py
  run_capturing route --check
  chmod 644 src/app/helpers2.py
  assert_eq "$captured_exit_code" "1"
  assert_contains "$captured_output" "could not parse src/app/helpers2.py"
  assert_not_contains "$captured_output" "Traceback"
fi
# Each stale allow says why; a guard's reviewer needs an agent file.
new_guard_repository guard-stale-reasons
gnu_sed -i 's|^  { pattern = .\^src/app/sub/., reason = "pure helpers, no orders" },$|&\n  { path = "src/app/money.py", reason = "a" },\n  { path = "src/app/helpers.py", reason = "b" },\n  { path = "src/app/ui.py", reason = "c" },\n  { path = "src/app/risk.py", reason = "d" },|' .claude/reviewers.toml
gnu_sed -i 's|^reviewer = "safety-reviewer"$|reviewer = "ghost-reviewer"|' .claude/reviewers.toml
run_capturing route --check
assert_contains "$captured_output" "allow src/app/ui.py is stale: nothing on the path matches it"
assert_contains "$captured_output" "reviewer 'ghost-reviewer' has no agent file"
gnu_sed -i 's|^reviewer = "ghost-reviewer"$|reviewer = "safety-reviewer"|' .claude/reviewers.toml
run_capturing route --check
assert_contains "$captured_output" "allow src/app/risk.py is stale: safety-reviewer reviews it now"
# Folders outside the repository and malformed module names are config errors.
new_guard_repository guard-paths
for bad in '"/src"' '"../src"'; do
  gnu_sed -i "s|^source_dirs = .*|source_dirs = [$bad]|" .claude/reviewers.toml
  expect_config_error "must be a folder inside the repository"
done
gnu_sed -i 's|^source_dirs = .*|source_dirs = ["src"]|; s|^entry_modules = .*|entry_modules = ["app..orders"]|' .claude/reviewers.toml
expect_config_error "must be a dotted module name"
# Config errors: another language, an allow entry without a reason or with both path and pattern.
new_guard_repository guard-config
printf '[[import_guards]]\nname = "x"\nlanguage = "rust"\nsource_dirs = ["src"]\nentry_modules = ["a"]\nreviewer = "r"\n' \
  | write_config
expect_config_error "import_guards[1].language"
printf '[[import_guards]]\nname = "x"\nlanguage = "python"\nsource_dirs = ["src"]\nentry_modules = ["a"]\nreviewer = "r"\nallow = [{ path = "a.py" }]\n' \
  | write_config
expect_config_error "import_guards[1].allow[1]: missing key 'reason'"
printf '[[import_guards]]\nname = "x"\nlanguage = "python"\nsource_dirs = ["src"]\nentry_modules = ["a"]\nreviewer = "r"\nallow = [{ path = "a.py", pattern = "^a", reason = "x" }]\n' \
  | write_config
expect_config_error "exactly one of path or pattern"

# --- The add-reviewer skill's files ----------------------------------------------------------------
# The example config is valid and passes --check in a project that has its agents and paths.
repository="$temporary_directory/example"
mkdir -p "$repository/.claude/agents"
cd "$repository"
git init --quiet
cp "$skill_directory/add-reviewer/reviewers.example.toml" .claude/reviewers.toml
for file_path in src/payments/charge.py src/payments/refund.py src/app/main.py migrations/0001_init.sql \
    tests/payments/test_charge_refunds.py docs/guide.md README.md CLAUDE.md package.json; do
  mkdir -p "$(dirname "$file_path")"; echo "x" > "$file_path"
done
for agent in payments-reviewer database-reviewer docs-reviewer; do
  printf -- '---\nname: %s\n---\n' "$agent" > ".claude/agents/$agent.md"
done
git add -A; git commit --quiet -m "chore: example"
run_capturing route --check
assert_eq "$captured_exit_code" "0"
# The commented model rules are the sizing policy (Opus for substantial logic, Fable for design, never
# Haiku); uncommented, they still pass --check.
example_rules=$(awk '/^# \[\[model_rules\]\]/{on=1} on && /^$/{on=0} on{sub(/^# ?/, ""); print}' \
  "$skill_directory/add-reviewer/reviewers.example.toml")
assert_contains "$example_rules" 'model = "opus"'
assert_contains "$example_rules" 'model = "fable"'
assert_not_contains "$(printf '%s' "$example_rules" | tr '[:upper:]' '[:lower:]')" "haiku"
printf '\n%s\n' "$example_rules" >> .claude/reviewers.toml
run_capturing route --check
assert_eq "$captured_exit_code" "0"
# The agent template carries the judge-only rule, the output groups and the verdict line.
template=$(cat "$skill_directory/add-reviewer/reviewer-template.md")
# shellcheck disable=SC2016  # the backticks are literal Markdown
for needle in "tools: Read, Grep, Glob, Bash" "model: sonnet" "effort: high" "read-only" "Do not re-run" "**Critical**" "**Important**" \
    "**Minor**" "Pre-existing (file as issues)" "gh issue create" '`SAFE TO LAND`' '`NOT SAFE: <why>`'; do
  assert_contains "$template" "$needle"
done
# The plugin's own default reviewer follows the same contract as the template.
change_reviewer=$(cat "$skill_directory/../agents/change-reviewer.md")
# shellcheck disable=SC2016  # the backticks are literal Markdown
for needle in "name: change-reviewer" "tools: Read, Grep, Glob, Bash" "model: sonnet" "effort: high" \
    "read-only" "Do not re-run" "**Critical**" "**Important**" "**Minor**" \
    "Pre-existing (file as issues)" '`SAFE TO LAND`' '`NOT SAFE: <why>`'; do
  assert_contains "$change_reviewer" "$needle"
done

# changed_line_matches: +++/--- are headers only before a file's first hunk; after it they are content.
python3 - "$script" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("reviewers_for_change", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
matches = module.changed_line_matches
header = "--- a/m.sql\n+++ b/m.sql\n"
git_header = "diff --git a/m.sql b/m.sql\nindex 1..2 100644\n" + header
checks = [
    (header + "@@ -1 +0,0 @@\n--- payments: keep\n", "-- payments", True),  # removed SQL comment
    (header + "@@ -0,0 +1 @@\n+++ x\n", r"\+\+ x", True),  # added "++ x"
    (header + "@@ -0,0 +1 @@\n+++ x\n", "x", True),
    (git_header + "@@ -1 +1 @@\n context\n", "m.sql|a/|b/", False),  # real headers never match
    (header, "m.sql", False),  # single-file patch, no hunk yet
    ("@@ -1 +1 @@\n--- payments\n", "payments", True),  # patch without headers
    # headers reset at the next file
    ("diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n+ok\ndiff --git a/b b/b\n--- a/b\n+++ b/zzz\n@@ -1 +1 @@\n ctx\n", "zzz", False),
    ("diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n+ok\ndiff --git a/b b/b\n--- a/b\n+++ b/b\n@@ -1 +1 @@\n--- zzz\n", "zzz", True),
    # only "\n" ends a line: other separators inside a line must not fake new lines
    (header + "@@ -1 +1 @@\n ctx\u2028+foo\n", "foo", False),  # false positive
    (header + "@@ -1 +1 @@\n ctx\x0cdiff --git a/x b/x\n+changed\n", "changed", True),  # false negative
    (header + "@@ -0,0 +1 @@\r\n+crlf\r\n", "^crlf$", True),  # trailing \r is not content
    # the pattern sees the line without its +/- prefix, so anchors work; removed lines count too
    (header + "@@ -0,0 +1 @@\n+DROP TABLE x;\n", "^DROP TABLE", True),
    (header + "@@ -1 +0,0 @@\n-DROP TABLE x;\n", "^DROP TABLE", True),
    (header + "@@ -0,0 +1 @@\n+x\n", r"^\+", False),
    (header + "@@ -0,0 +1 @@\n+\n", "^$", True),  # an added blank line is a changed line
    (header + "@@ -0,0 +1 @@\n+++ x\n", r"^\+\+ x", True),
    ("diff --git a/m.sql b/m.sql\n" + header + "@@ -1 +1 @@\n context\n", "^-- a", False),
]
for patch, pattern, expected in checks:
    assert matches(patch, re.compile(pattern)) is expected, (patch, pattern, expected)
PY
