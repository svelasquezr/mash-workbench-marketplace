# shellcheck shell=bash
# Write scope: each script that writes changes only the places it may, and each script that only reads changes nothing.
# For every case the test lists four folders before and after, and asserts that each path that changed is on the
# case's allowed list:
#   - the fixture parent (every fixture repository, with its git directory),
#   - a fresh HOME,
#   - a private TMPDIR,
#   - the copy of the plugin that every script here runs from (a script must not write next to itself).
# It lists every file with its checksum, and every file, directory and symbolic link with its mode, so a new file, a
# changed file, a changed mode and a new folder all show. A case that changes nothing fails too, so the test cannot
# pass because a script did not run. find -newer is not used: it misses files written in the same timestamp tick.
# The allowed places are the repository's home folder (.claude/mash-workbench/), the repository's info/exclude, and for
# the backlog the backlog file.
# Not covered: a write to any folder outside those four, for example a fixed path under /var/tmp, an absolute path
# under the real home folder, or the installed plugin cache. A script that wrote there would pass this test, so it is
# a tripwire for the common mistakes, not a proof. tests/test_backlog_add.sh and test_mash_settings.sh
# hold the cases where a script must refuse to write (a committed settings file or a symbolic
# link that leads outside the repository).
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
# The path checks refuse /tmp, so the area lives under the real $HOME (never under /tmp).
area=$(mktemp -d "$HOME/.write-scope-test.XXXXXX"); trap 'rm -rf "$area"' EXIT
case "$(cd "$area" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
area=$(cd "$area" && pwd -P)
mkdir -p "$area/config" "$area/fixtures" "$area/home" "$area/tmp" "$area/lists" "$area/plugin-copy"
# Every script runs from a private copy of the plugins, which is listed like the other folders: a write next to a
# script shows, and other tests that run in parallel cannot add a __pycache__ to what is checked.
cp -R "$PWD/plugins/mash-workbench" "$area/plugin-copy/"
find "$area/plugin-copy" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
copy="$area/plugin-copy"
settings_script="$copy/mash-workbench/scripts/mash-settings.sh"
python_finder="$copy/mash-workbench/scripts/python.sh"
backlog_add="$copy/mash-workbench/skills/scout/backlog-add.sh"
backlog_stale="$copy/mash-workbench/skills/scout/backlog-stale.sh"
friction="$copy/mash-workbench/scripts/past-friction.py"
temporary_directory="$area/config"
isolate_git_config
# From here the scripts see the fresh HOME and a private TMPDIR, both listed before and after each case.
export HOME="$area/home" TMPDIR="$area/tmp"
unset REVIEW_ROUTING_ESCAPES MASH_WORKBENCH_BACKLOG ESCAPE_DATE BACKLOG_DATE CLAUDE_CONFIG_DIR
fixtures="$area/fixtures"
fresh_home="$area/home"
mkdir -p "$fresh_home/.claude"
printf '{}\n' > "$fresh_home/.claude/settings.json"
printf 'alias x=true\n' > "$fresh_home/.bashrc"

# new_repo <name>: a repository with one commit; prints its path.
new_repo() {
  local folder
  folder=$(mktemp -d "$fixtures/$1.XXXXXX")
  git init --quiet "$folder"
  git -C "$folder" commit --quiet --allow-empty -m "chore: base"
  (cd "$folder" && pwd -P)
}
# listing <name>: sorted lines for everything under the four folders: "<crc> <size> <path>" for each file, and
# "M <mode> <path>" for every file, directory and symbolic link (a link also shows its target).
listing() {
  {
    find "$fixtures" "$fresh_home" "$TMPDIR" "$copy" -type f -exec cksum {} + 2>/dev/null || true
    find "$fixtures" "$fresh_home" "$TMPDIR" "$copy" -exec ls -ld {} + 2>/dev/null \
      | awk '{ if (substr($1, 1, 1) == "l") print "M", $1, $(NF-2), $NF; else print "M", $1, $NF }' || true
  } | sort > "$area/lists/$1"
}
# changed_paths <before> <after>: the paths added, removed or changed between two listings (a mode line starts with M).
changed_paths() {
  { diff "$area/lists/$1" "$area/lists/$2" || true; } \
    | sed -n -e 's/^[<>] M [^ ]* //p' -e 's/^[<>] [0-9][0-9]* [0-9][0-9]* //p' | sed 's/ .*//' | sort -u
}
# assert_no_change <case name>: nothing under the four folders changed (a read-only script).
assert_no_change() {
  listing after
  if ! cmp -s "$area/lists/before" "$area/lists/after"; then
    printf '  case "%s" changed something, and it may not:\n' "$1"
    changed_paths before after
    exit 1
  fi
}
# assert_scope <case name> <allowed glob>...: runs after "listing before" and the script; lists "after" and checks.
# A directory is also allowed when it is, or holds, the base of an allowed glob (the script made the folder).
assert_scope() {
  local name="$1" changed path ok pattern base count=0
  shift
  listing after
  changed=$(changed_paths before after)
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    count=$((count + 1))
    ok=0
    for pattern in "$@"; do
      base=${pattern%/\*}
      # shellcheck disable=SC2053  # the pattern is a glob on purpose
      if [[ "$path" == $pattern ]]; then ok=1; break; fi
      if [[ -d "$path" && ( "$path" == "$base" || "$base" == "$path"/* ) ]]; then ok=1; break; fi
    done
    if [[ $ok == 0 ]]; then printf '  case "%s" changed something outside its allowed places: %s\n' "$name" "$path"; exit 1; fi
  done <<< "$changed"
  if [[ $count == 0 ]]; then printf '  case "%s" changed nothing: the script did not write\n' "$name"; exit 1; fi
}

# 0. The check itself: a script that writes next to itself, in the fresh HOME or in TMPDIR is caught.
repo=$(new_repo selfcheck)
for stray in "$copy/mash-workbench/scripts/leak" "$fresh_home/.leak" "$TMPDIR/leak"; do
  listing before
  printf 'x\n' > "$stray"
  listing after
  assert_eq "$(changed_paths before after)" "$stray"
  rm "$stray"
done

# 6. mash-settings.sh set --team: the settings file only.
repo=$(new_repo settings)
listing before
bash "$settings_script" set "$repo" escapes .claude/mash-workbench/escapes --team >/dev/null
assert_scope "mash-settings set --team" "$repo/.claude/mash-workbench/settings"
# 6b. set --local: settings.local and the repository's info/exclude.
listing before
bash "$settings_script" set "$repo" escapes.threshold 4 --local >/dev/null
assert_scope "mash-settings set --local" "$repo/.claude/mash-workbench/settings.local" "$repo/.git/info/exclude"
# 6c. unset: the settings file that held the key.
listing before
bash "$settings_script" unset "$repo" escapes --team >/dev/null
assert_scope "mash-settings unset" "$repo/.claude/mash-workbench/settings"

# 8. backlog-add.sh: the backlog file the setting names, and nothing else; the file is new, so its folder is too.
repo=$(new_repo backlog)
bash "$settings_script" set "$repo" backlog docs/mash/tooling-backlog.md --team >/dev/null
listing before
BACKLOG_DATE=2026-11-01 bash "$in_root_script" "$backlog_add" "$repo" script "Check the lockfile" "CI failed twice" >/dev/null
assert_scope "backlog-add" "$repo/docs/mash/tooling-backlog.md"
# 8b. From a linked worktree: the main worktree's file changes; the worktree stays untouched.
mkdir -p "$repo/.claude"
git -C "$repo" worktree add --quiet -b w1 "$repo/.claude/worktrees/w1"
listing before
BACKLOG_DATE=2026-11-01 bash "$in_root_script" "$backlog_add" "$repo/.claude/worktrees/w1" hook "Block force pushes" "twice" >/dev/null
assert_scope "backlog-add from a linked worktree" "$repo/docs/mash/tooling-backlog.md"
# 8c. An old backlog with no setting and no owner line: the file is rewritten in place (the owner line, the entry),
# and the temporary copy next to it is gone.
repo=$(new_repo backlogold)
mkdir -p "$repo/docs"; printf '# Tooling backlog\n\n' > "$repo/docs/tooling-backlog.md"
listing before
BACKLOG_DATE=2026-11-01 bash "$in_root_script" "$backlog_add" "$repo" script "Check the lockfile" "CI failed twice" >/dev/null 2>&1
assert_scope "backlog-add to an old backlog" "$repo/docs/tooling-backlog.md"
assert_contains "$(cat "$repo/docs/tooling-backlog.md")" "repo: local/"
# 8d. backlog-stale.sh only reads.
listing before
BACKLOG_TODAY=2027-01-01 bash "$backlog_stale" "$repo" > "$area/lists/stale.out"
assert_contains "$(cat "$area/lists/stale.out")" "Check the lockfile"
assert_no_change "backlog-stale"

# 10. past-friction.py reads transcripts under a projects folder in the fresh HOME and prints what recurs: nothing
# changes. Two sessions hold the same correction, so the script reaches the code that prints one.
repo=$(new_repo friction)
slug=$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9-]/-/g')
mkdir -p "$fresh_home/.claude/projects/$slug"
today=$(date -u +%F)
printf '{"type":"user","message":{"role":"user","content":"No, never amend commits on the review branch"},"timestamp":"%sT10:00:00.000Z"}\n' "$today" > "$fresh_home/.claude/projects/$slug/s1.jsonl"
printf '{"type":"user","message":{"role":"user","content":"I told you: never amend commits on a review branch"},"timestamp":"%sT11:00:00.000Z"}\n' "$today" > "$fresh_home/.claude/projects/$slug/s2.jsonl"
listing before
bash "$python_finder" "$friction" --project "$repo" --projects-dir "$fresh_home/.claude/projects" > "$area/lists/friction.out"
assert_contains "$(cat "$area/lists/friction.out")" "correction · 2 sessions"
assert_no_change "past-friction"

# 11. permission-rules.sh reads the settings.local.json files and the worktree list and prints rules: nothing changes.
repo=$(new_repo rules)
mkdir -p "$repo/.claude"
printf '{"permissions": {"allow": ["Bash(bash /x/cache/mash-workbench/0.0.0/skills/scout/backlog-add.sh *)"]}}\n' > "$repo/.claude/settings.local.json"
listing before
bash "$copy/mash-workbench/skills/scout/permission-rules.sh" "$repo" > "$area/lists/rules.out"
assert_contains "$(cat "$area/lists/rules.out")" "remove:"
assert_contains "$(cat "$area/lists/rules.out")" "backlog-add.sh *)"
assert_no_change "permission-rules"

# 13. plugin-current.sh only reads.
listing before
bash "$copy/mash-workbench/scripts/plugin-current.sh"
assert_no_change "plugin-current"
echo "write scope: ok"
