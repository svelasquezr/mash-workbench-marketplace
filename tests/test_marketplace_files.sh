# shellcheck shell=bash
# The marketplace is listed twice, for two tools: .claude-plugin/marketplace.json (Claude Code) and
# .github/plugin/marketplace.json (GitHub Copilot CLI). They must say the same thing, and every entry must name a
# plugin folder that exists and whose plugin.json carries the same name.
set -euo pipefail
source tests/lib.sh
claude_catalog=.claude-plugin/marketplace.json
copilot_catalog=.github/plugin/marketplace.json

for catalog in "$claude_catalog" "$copilot_catalog"; do
  [[ -f "$catalog" ]] || { echo "FAIL: $catalog is missing" >&2; exit 1; }
  python3 -m json.tool "$catalog" >/dev/null
done

assert_eq "$(python3 -c 'import json, sys; a, b = (json.load(open(p)) for p in sys.argv[1:]); print(a == b)' "$claude_catalog" "$copilot_catalog")" "True"

listed=$(python3 - "$claude_catalog" <<'PY'
import json, sys
for plugin in json.load(open(sys.argv[1]))["plugins"]:
    folder = plugin["source"].removeprefix("./")
    manifest = json.load(open(f"{folder}/.claude-plugin/plugin.json"))
    assert manifest["name"] == plugin["name"], (plugin["name"], manifest["name"])
    assert manifest["description"] == plugin["description"], f'{plugin["name"]}: catalog and plugin.json descriptions differ'
    print(plugin["name"])
PY
)
assert_eq "$listed" "$(printf 'mash-workbench\nreview-routing')"

# Every plugin folder is listed.
assert_eq "$(find plugins -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "$(grep -c . <<< "$listed")"
