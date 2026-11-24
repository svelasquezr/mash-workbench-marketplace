# shellcheck shell=bash
# Convention (ADRs 0007, 0008): plugins are instructions only. No plugin ships a .sh or .py file, and no skill file names a
# script path ("<this skill's base directory>/<path>.sh" or ".py", or a "scripts/" folder of the plugin).
# tests/test_skill_references.sh checks only quoted section names, not script paths.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

script_path_pattern="\(<this skill's base directory>/\|scripts/\)[^][:space:]\`'\"<>()]*\.\(sh\|py\)"

# script_path_problems <file>: one line for each script path the skill file names.
script_path_problems() {
  { grep -o "$script_path_pattern" "$1" || true; } | sort -u | while IFS= read -r match; do
    echo "$1: names a script: $match"
  done
}

# shipped_scripts <plugin folder>: the .sh and .py files of the plugin, outside evals/ (the setup scripts of eval cases
# run only under `claude plugin eval --scaffold`, never in a user's session).
shipped_scripts() {
  find "$1" -path "$1/evals" -prune -o \( -name '*.sh' -o -name '*.py' \) -print
}

# The checks catch a script path and a shipped script, and pass a plain skill and an eval setup script.
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/p/skills/a" "$scratch/p/evals/case"
: > "$scratch/p/evals/case/setup.sh"
# shellcheck disable=SC2016  # the backticks are text in the fixture
printf 'run `bash <this skill'"'"'s base directory>/../b/x.sh <repo>`.\n' > "$scratch/p/skills/a/SKILL.md"
assert_eq "$(script_path_problems "$scratch/p/skills/a/SKILL.md")" "$scratch/p/skills/a/SKILL.md: names a script: <this skill's base directory>/../b/x.sh"
printf 'no script here.\n' > "$scratch/p/skills/a/SKILL.md"
assert_eq "$(script_path_problems "$scratch/p/skills/a/SKILL.md")" ""
# shellcheck disable=SC2016  # the backticks are text in the fixture
printf 'run `bash ../../scripts/y.py`.\n' > "$scratch/p/skills/a/SKILL.md"
assert_eq "$(script_path_problems "$scratch/p/skills/a/SKILL.md")" "$scratch/p/skills/a/SKILL.md: names a script: scripts/y.py"
assert_eq "$(shipped_scripts "$scratch/p")" ""
: > "$scratch/p/skills/a/run.py"
assert_eq "$(shipped_scripts "$scratch/p")" "$scratch/p/skills/a/run.py"

problems=""
for plugin_directory in plugins/*/; do
  plugin_directory=${plugin_directory%/}
  shipped=$(shipped_scripts "$plugin_directory")
  [[ -z "$shipped" ]] || problems+="$plugin_directory ships scripts: $shipped"$'\n'
  [[ ! -d "$plugin_directory/scripts" ]] || problems+="$plugin_directory has a scripts/ folder"$'\n'
  while IFS= read -r file; do
    problem=$(script_path_problems "$file")
    [[ -z "$problem" ]] || problems+="$problem"$'\n'
  done < <(find "$plugin_directory/skills" -name '*.md')
done
assert_eq "$problems" ""
