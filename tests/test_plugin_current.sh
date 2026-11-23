# shellcheck shell=bash
# plugin-current.sh: a copy of a plugin that Claude Code left in its plugin cache after an update must not run. An allow
# rule names one exact path, so a rule that the user accepted for an old version still approves the old version's
# scripts; the scripts that get allow rules ask plugin-current.sh first and stop when their copy is not installed.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
# The same file ships in each MASH plugin.
assert_eq "$(cmp plugins/review-routing/scripts/plugin-current.sh plugins/mash-workbench/scripts/plugin-current.sh && echo same)" "same"
# The path checks refuse /tmp, so the fixture lives under $HOME.
fixture=$(mktemp -d "$HOME/.plugin-current-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
fixture=$(cd "$fixture" && pwd -P)
temporary_directory="$fixture"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES MASH_WORKBENCH_BACKLOG

# install <config folder> <marketplace> <plugin> <version>: a copy of the plugin where Claude Code keeps one; prints it.
install() {
  local target="$1/plugins/cache/$2/$3/$4"
  mkdir -p "$(dirname "$target")"
  cp -R "plugins/$3" "$target"
  printf '%s' "$target"
}
# registry <config folder> <installPath>...: an installed_plugins.json that names those paths.
registry() {
  local file="$1/plugins/installed_plugins.json" path separator=""
  shift
  {
    printf '{\n  "version": 2,\n  "plugins": {\n    "x@m": [\n'
    for path in "$@"; do
      printf '%s      {\n        "scope": "user",\n        "installPath": "%s",\n        "version": "1"\n      }' "$separator" "$path"
      separator=$',\n'
    done
    printf '\n    ]\n  }\n}\n'
  } > "$file"
}
config="$fixture/config"
old=$(install "$config" m review-routing 0.5.1)
new=$(install "$config" m review-routing 0.6.0)

# 1. Not in a plugin cache (a clone, --plugin-dir): nothing to compare, the copy runs.
run_capturing bash plugins/review-routing/scripts/plugin-current.sh
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""
# A folder of the cache shape with no installed_plugins.json next to it is not Claude Code's cache.
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"

# 2. The registry names only the new version: the new copy runs, the old copy stops with exit 6.
registry "$config" "$new"
run_capturing bash "$new/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "review-routing 0.5.1"
assert_contains "$captured_output" "not the installed version"

# 3. Project entries. A registry lists old versions for many old projects, so an entry with a projectPath counts only
#    for that project: the current folder, a folder above it, or the main worktree of the current folder's repository.
# project_registry <installPath> <projectPath>: the new version for the user, and one project entry.
project_registry() {
  printf '{"version": 2, "plugins": {"review-routing@m": [{"scope": "user", "installPath": "%s", "version": "0.6.0"}, {"projectPath": "%s", "scope": "project", "version": "0.5.1", "installPath": "%s"}]}}\n' \
    "$new" "$2" "$1" > "$config/plugins/installed_plugins.json"
}
project="$fixture/project"; git init --quiet "$project"; git -C "$project" commit --quiet --allow-empty -m "chore: base"
mkdir -p "$project/src" "$fixture/other-project"
git -C "$project" worktree add --quiet "$project/.claude/worktrees/w1" -b w1
# run_in <folder> <script>: run the check with that current folder.
# shellcheck disable=SC2016  # the inner bash expands $1 and $2
run_in() { run_capturing bash -c 'cd "$1" && bash "$2"' _ "$1" "$2"; }
project_registry "$old" "$fixture/other-project"
for folder in "$project" "$PWD"; do
  run_in "$folder" "$old/scripts/plugin-current.sh"
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "not the installed version for this folder"
done
run_in "$fixture/other-project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
project_registry "$old" "$project"
for folder in "$project" "$project/src" "$project/.claude/worktrees/w1"; do
  run_in "$folder" "$old/scripts/plugin-current.sh"
  assert_eq "$captured_exit_code" "0"
done
# A project entry for a folder above the project (the home folder, say) is not an entry for this project.
project_registry "$old" "$fixture"
run_in "$project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
project_registry "$old" "$project"
# The projectPath belongs to the object that holds it: an entry with a nested object before or after its keys is
# still a project entry, not a user entry.
printf '{"plugins": {"x@m": [{"installPath": "%s", "meta": {"a": 1}, "projectPath": "%s"}, {"meta": {"b": {}}, "projectPath": "%s", "installPath": "%s"}]}}\n' \
  "$old" "$fixture/other-project" "$fixture/other-project" "$old" > "$config/plugins/installed_plugins.json"
run_in "$project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
run_in "$fixture/other-project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
project_registry "$old" "$project"
run_in "$fixture/other-project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
# The user's own version runs from every folder.
run_in "$fixture/other-project" "$new/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"

# 4. Windows spells the path with escaped backslashes and a drive letter; only the end of the path is compared.
registry "$config" 'C:\\Users\\me\\.claude\\plugins\\cache\\M\\review-routing\\0.6.0'
run_capturing bash "$new/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
# Another marketplace's plugin of the same name and version is another copy.
registry "$config" "$config/plugins/cache/other/review-routing/0.5.1" "$config/plugins/cache/m/review-routing/0.5.10"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"

# 5. A registry in which no installPath is found (another format) cannot answer: the copy runs.
printf '{"version": 3, "plugins": []}\n' > "$config/plugins/installed_plugins.json"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"

# 5b. When the copy is in a cache-shaped folder and the check cannot answer, it says so on stderr (one line), and
#     the copy runs: no registry, an empty registry, a registry cut in the middle of a write.
rm "$config/plugins/installed_plugins.json"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "cannot tell"
: > "$config/plugins/installed_plugins.json"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "cannot tell"
printf '{"version": 2, "plugins": {"x@m": [{"scope": "user", "installPa' > "$config/plugins/installed_plugins.json"
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
assert_eq "$(printf '%s\n' "$captured_output" | wc -l | tr -d ' ')" "1"
assert_contains "$captured_output" "cannot tell"
# A copy outside every cache folder stays silent.
run_capturing bash plugins/review-routing/scripts/plugin-current.sh
assert_eq "$captured_output" ""
# null, true, false and numbers are values: "projectPath": null is a user entry, and the key after it is a key.
printf '{"version": 2, "plugins": {"x@m": [{"projectPath": null, "enabled": true, "size": 12.5, "installPath": "%s"}]}}\n' "$new" > "$config/plugins/installed_plugins.json"
run_capturing bash "$new/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""
run_capturing bash "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
# 5c. The project comes from where the current folder really is. A folder of project B that is shaped like a git
#     directory whose core.worktree names project A does not make B count as A.
project_registry "$old" "$project"
fake_git="$fixture/other-project/fake"
git init --quiet --bare "$fake_git"
git --git-dir="$fake_git" config core.bare false
git --git-dir="$fake_git" config core.worktree "$project"
run_in "$fake_git" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
run_in "$project" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "0"
# The same folder with core.worktree ../.. (a folder above project B, inside it as git sees it): an entry for the
# folder above still does not count. No git runs in a folder shaped like a git directory.
project_registry "$old" "$fixture"
git --git-dir="$fake_git" config core.worktree ../..
run_in "$fake_git" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"
mkdir -p "$fake_git/sub"
run_in "$fake_git/sub" "$old/scripts/plugin-current.sh"
assert_eq "$captured_exit_code" "6"

# 6. The scripts that get allow rules stop in an old copy, before they read an argument or write a file.
registry "$config" "$new"
repo="$fixture/repo"; git init --quiet "$repo"; git -C "$repo" commit --quiet --allow-empty -m "chore: base"
printf 'a\n' > "$repo/a"; git -C "$repo" add a; git -C "$repo" commit --quiet -m "feat: a"
mash_old=$(install "$config" m mash-workbench 0.2.5)
mash_new=$(install "$config" m mash-workbench 0.3.0)
registry "$config" "$new" "$mash_new"
before=$(find "$repo" -path "$repo/.git" -prune -o -print | sort)
for command in "$old/skills/add-reviewer/escape-add.sh $repo src/a wrong-result slug --body text" \
  "$old/skills/add-reviewer/escape-add.sh --list $repo src/a" \
  "$old/skills/review-changes/review-log.sh add $repo HEAD~1 HEAD" \
  "$old/skills/review-changes/review-log.sh reviewed $repo HEAD" \
  "$mash_old/skills/scout/backlog-add.sh $repo script title why"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing env REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes MASH_WORKBENCH_BACKLOG=docs/backlog.md bash $command
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "not the installed version"
done
assert_eq "$(find "$repo" -path "$repo/.git" -prune -o -print | sort)" "$before"
# The installed copies run.
run_capturing env REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes bash "$in_root_script" "$new/skills/add-reviewer/escape-add.sh" "$repo" src/a wrong-result slug --body "When X, Y."
assert_eq "$captured_exit_code" "0"
run_capturing bash "$in_root_script" "$new/skills/review-changes/review-log.sh" add "$repo" HEAD~1 HEAD
assert_eq "$captured_exit_code" "0"
run_capturing env MASH_WORKBENCH_BACKLOG=docs/backlog.md bash "$in_root_script" "$mash_new/skills/scout/backlog-add.sh" "$repo" script title why
assert_eq "$captured_exit_code" "0"
echo "plugin current: ok"
