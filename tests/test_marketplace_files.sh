# shellcheck shell=bash
# The marketplace is listed twice, for two tools: .claude-plugin/marketplace.json (Claude Code) and
# .github/plugin/marketplace.json (GitHub Copilot CLI). They must say the same thing, and every entry must name a
# plugin folder that exists and whose plugin.json carries the same name and description.
#
# A catalog entry is a component carrier too: Claude Code merges an entry's hooks, commands, agents, skills, MCP or
# LSP servers (and more) into the plugin it installs, and a `source` can point anywhere. So both catalogs are
# allow-listed key by key, and each entry's source is pinned to ./plugins/<name> (docs/decisions/0004).
set -euo pipefail
source tests/lib.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
claude_catalog=.claude-plugin/marketplace.json
copilot_catalog=.github/plugin/marketplace.json

# catalog_problems <catalog>: one line per broken rule; plugin folders are read relative to the current directory.
catalog_problems() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
catalog_path = sys.argv[1]
problems = []
top_keys = {"name", "description", "owner", "plugins"}
owner_keys = {"name", "email"}
entry_keys = {"name", "description", "source", "category"}
try:
    catalog = json.load(open(catalog_path, encoding="utf-8"))
    problems += [f"declares {key}" for key in sorted(set(catalog) - top_keys)]
    problems += [f"owner declares {key}" for key in sorted(set(catalog.get("owner", {})) - owner_keys)]
    for entry in catalog["plugins"]:
        name = entry["name"]
        problems += [f"{name}: declares {key}" for key in sorted(set(entry) - entry_keys)]
        if entry["source"] != f"./plugins/{name}":
            problems.append(f"{name}: source must be ./plugins/{name}, not {entry['source']!r}")
            continue
        manifest = json.load(open(Path("plugins", name, ".claude-plugin", "plugin.json"), encoding="utf-8"))
        if manifest["name"] != name:
            problems.append(f"{name}: plugin.json is named {manifest['name']!r}")
        if manifest["description"] != entry["description"]:
            problems.append(f"{name}: catalog and plugin.json descriptions differ")
except Exception as error:
    problems.append(f"could not be checked: {type(error).__name__}: {error}")
print("\n".join(problems))
PY
}

# Each rule catches what it is for (fixtures run from a scratch folder with one plugin).
mkdir -p "$temporary_directory/plugins/p/.claude-plugin"
printf '{"name": "p", "description": "d"}\n' > "$temporary_directory/plugins/p/.claude-plugin/plugin.json"
check_fixture() { printf '%s\n' "$1" > "$temporary_directory/catalog.json"; (cd "$temporary_directory" && catalog_problems catalog.json); }
entry='"name": "p", "description": "d", "source": "./plugins/p"'
problems=$(check_fixture "{\"name\": \"m\", \"owner\": {\"name\": \"o\"}, \"plugins\": [{$entry, \"category\": \"c\"}]}"); assert_eq "$problems" ""
assert_contains "$(check_fixture "{\"plugins\": [{$entry, \"hooks\": {}}]}")" "p: declares hooks"
assert_contains "$(check_fixture "{\"plugins\": [{$entry, \"headersHelper\": \"x\"}]}")" "p: declares headersHelper"
assert_contains "$(check_fixture "{\"metadata\": {\"pluginRoot\": \"./x\"}, \"plugins\": [{$entry}]}")" "declares metadata"
assert_contains "$(check_fixture "{\"owner\": {\"name\": \"o\", \"url\": \"x\"}, \"plugins\": [{$entry}]}")" "owner declares url"
assert_contains "$(check_fixture '{"plugins": [{"name": "p", "description": "d", "source": "../elsewhere"}]}')" "p: source must be ./plugins/p"
assert_contains "$(check_fixture '{"plugins": [{"name": "p", "description": "d", "source": {"source": "github", "repo": "o/r"}}]}')" "p: source must be ./plugins/p"
assert_contains "$(check_fixture '{"plugins": [{"name": "p", "description": "other", "source": "./plugins/p"}]}')" "p: catalog and plugin.json descriptions differ"
assert_contains "$(check_fixture '{"plugins": [{"name": "p",')" "could not be checked: JSONDecodeError"
assert_contains "$(check_fixture '{"plugins": [{"name": "q", "description": "d", "source": "./plugins/q"}]}')" "could not be checked: FileNotFoundError"
mkdir -p "$temporary_directory/plugins/r/.claude-plugin"
printf '{"name": "other", "description": "d"}\n' > "$temporary_directory/plugins/r/.claude-plugin/plugin.json"
assert_contains "$(check_fixture '{"plugins": [{"name": "r", "description": "d", "source": "./plugins/r"}]}')" "r: plugin.json is named 'other'"

# Both catalogs exist, are identical and pass. Outputs are captured first, so a crash stops the test (set -e).
for catalog in "$claude_catalog" "$copilot_catalog"; do
  [[ -f "$catalog" ]] || { echo "FAIL: $catalog is missing" >&2; exit 1; }
  problems=$(catalog_problems "$catalog"); assert_eq "$problems" ""
done
same=$(python3 -c 'import json, sys; a, b = (json.load(open(p)) for p in sys.argv[1:]); print(a == b)' "$claude_catalog" "$copilot_catalog")
assert_eq "$same" "True"

# Every plugin folder is listed, and nothing else.
listed=$(python3 -c 'import json, sys; print("\n".join(sorted(p["name"] for p in json.load(open(sys.argv[1]))["plugins"])))' "$claude_catalog")
folders=$(find plugins -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
assert_eq "$listed" "$folders"
assert_eq "$listed" "$(printf 'mash-workbench\nreview-routing')"
