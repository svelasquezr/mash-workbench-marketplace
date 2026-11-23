# shellcheck shell=bash
# Convention: every script path a skill of a plugin that ships scripts writes as "<this skill's base directory>/<path>.sh" or ".py", in any SKILL.md or
# reference.md, names a file that exists (relative to that skill's folder, so "../scout/x.sh" counts). A plugin with no .sh or .py files (mash-review) is skipped; the
# sanity scan below runs on mash-workbench, the plugin that has scripts.
# tests/test_skill_references.sh checks only quoted section names, not script paths.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

# missing_scripts <file>: prints one line for each script path in the file that does not resolve.
missing_scripts() {
  local file=$1 folder path
  folder=$(dirname "$file")
  { grep -o "<this skill's base directory>/[^][:space:]\`'\"<>()]*\.\(sh\|py\)" "$file" || true; } | sort -u | while IFS= read -r match; do
    path=${match#"<this skill's base directory>/"}
    [[ -f "$folder/$path" ]] || echo "$file: no such script: $path"
  done
}

# The check catches a missing script and accepts an existing one, also through "..".
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/one" "$scratch/two"
: > "$scratch/two/real.sh"
# shellcheck disable=SC2016  # the backticks are text in the fixture
printf 'run `bash <this skill'"'"'s base directory>/../two/real.sh <repo>` and `bash <this skill'"'"'s base directory>/gone.sh`.\n' > "$scratch/one/SKILL.md"
assert_eq "$(missing_scripts "$scratch/one/SKILL.md")" "$scratch/one/SKILL.md: no such script: gone.sh"

# The scan finds paths at all (a pattern that matches nothing would pass every file).
found=$(grep -o "<this skill's base directory>/[^][:space:]\`'\"<>()]*\.\(sh\|py\)" plugins/mash-workbench/skills/scout/SKILL.md | wc -l | tr -d ' ')
[[ "$found" -ge 1 ]] || { echo "  the scan found no script paths in scout/SKILL.md"; exit 1; }

problems=""
for file in plugins/*/skills/*/SKILL.md plugins/*/skills/*/reference.md; do
  [[ -f "$file" ]] || continue
  # Only a plugin that ships scripts (mash-workbench) is checked: a plugin with none, like mash-review, is
  # instructions only, and the paths it writes are not script paths.
  plugin_directory=${file#plugins/}; plugin_directory=plugins/${plugin_directory%%/*}
  [[ -d "$plugin_directory/scripts" || -n "$(find "$plugin_directory" -name '*.sh' -o -name '*.py' | head -n 1)" ]] || continue
  problems+=$(missing_scripts "$file")
done
assert_eq "$problems" ""
