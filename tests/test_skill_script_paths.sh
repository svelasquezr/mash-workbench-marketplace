# shellcheck shell=bash
# Convention: every script path a skill of a plugin that ships scripts writes as "<this skill's base directory>/<path>.sh" or ".py", in any SKILL.md or
# reference.md, names a file that exists (relative to that skill's folder, so "../scout/x.sh" counts). A plugin that ships no .sh or .py file outside its evals/ folder
# (mash-review) is instructions only, so its skills must name no script path at all. The sanity scan below runs on
# mash-workbench, the plugin that has scripts.
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

# ships_scripts <plugin folder>: true when the plugin has a scripts/ folder or a .sh or .py file outside evals/ (the
# setup scripts of eval cases run only under `claude plugin eval --scaffold`, never in a user's session).
ships_scripts() {
  [[ -d "$1/scripts" || -n "$(find "$1" -path "$1/evals" -prune -o \( -name '*.sh' -o -name '*.py' \) -print | head -n 1)" ]]
}
# script_path_problems <file> <plugin folder>: the problems of one skill file.
script_path_problems() {
  if ships_scripts "$2"; then
    missing_scripts "$1"
  elif grep -q "<this skill's base directory>/[^][:space:]\`'\"<>()]*\.\(sh\|py\)" "$1"; then
    echo "$1: names a script, but the plugin ships none"
  fi
}

# A plugin with no scripts fails when a skill names one; an eval setup script does not count as shipping one.
mkdir -p "$scratch/plain/skills/a" "$scratch/plain/evals/case"
: > "$scratch/plain/evals/case/setup.sh"
printf 'run `bash <this skill'"'"'s base directory>/x.sh`.\n' > "$scratch/plain/skills/a/SKILL.md"
assert_eq "$(script_path_problems "$scratch/plain/skills/a/SKILL.md" "$scratch/plain")" "$scratch/plain/skills/a/SKILL.md: names a script, but the plugin ships none"
printf 'no script here.\n' > "$scratch/plain/skills/a/SKILL.md"
assert_eq "$(script_path_problems "$scratch/plain/skills/a/SKILL.md" "$scratch/plain")" ""

# The scan finds paths at all (a pattern that matches nothing would pass every file).
found=$(grep -o "<this skill's base directory>/[^][:space:]\`'\"<>()]*\.\(sh\|py\)" plugins/mash-workbench/skills/scout/SKILL.md | wc -l | tr -d ' ')
[[ "$found" -ge 1 ]] || { echo "  the scan found no script paths in scout/SKILL.md"; exit 1; }

problems=""
for file in plugins/*/skills/*/SKILL.md plugins/*/skills/*/reference.md; do
  [[ -f "$file" ]] || continue
  plugin_directory=${file#plugins/}; plugin_directory=plugins/${plugin_directory%%/*}
  problem=$(script_path_problems "$file" "$plugin_directory")
  [[ -z "$problem" ]] || problems+="$problem"$'\n'
done
assert_eq "$problems" ""
