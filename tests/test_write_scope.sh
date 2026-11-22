# shellcheck shell=bash
# Write scope: each script that writes changes only the places it may, and each script that only reads changes nothing.
# For every case the test lists four folders before and after, and asserts that each path that changed is on the
# case's allowed list:
#   - the fixture parent (every fixture repository, with its git directory),
#   - a fresh HOME,
#   - a private TMPDIR,
#   - the copy of the two plugins that every script here runs from (a script must not write next to itself).
# It lists every file with its checksum, and every file, directory and symbolic link with its mode, so a new file, a
# changed file, a changed mode and a new folder all show. A case that changes nothing fails too, so the test cannot
# pass because a script did not run. find -newer is not used: it misses files written in the same timestamp tick.
# The allowed places are the repository's home folder (.claude/mash-workbench/), the chosen escapes folder, the
# repository's info/exclude, and for the backlog the backlog file.
# Not covered: a write to any folder outside those four, for example a fixed path under /var/tmp, an absolute path
# under the real home folder, or the installed plugin cache. A script that wrote there would pass this test, so it is
# a tripwire for the common mistakes, not a proof. tests/test_escapes.sh, test_backlog_add.sh, test_mash_settings.sh
# and test_review_log.sh hold the cases where a script must refuse to write (a committed settings file or a symbolic
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
cp -R "$PWD/plugins/review-routing" "$PWD/plugins/mash-workbench" "$area/plugin-copy/"
find "$area/plugin-copy" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
copy="$area/plugin-copy"
add="$copy/review-routing/skills/add-reviewer/escape-add.sh"
migrate="$copy/review-routing/skills/add-reviewer/escape-migrate.sh"
report="$copy/review-routing/skills/add-reviewer/escapes-report.sh"
settings_script="$copy/review-routing/scripts/mash-settings.sh"
review_log="$copy/review-routing/skills/review-changes/review-log.sh"
python_finder="$copy/review-routing/scripts/python.sh"
router="$copy/review-routing/skills/review-changes/reviewers-for-change.py"
guard="$copy/review-routing/hooks/reviewer-guard.py"
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
body_text='When the order has a discount, the total includes tax. The total must not include tax. Tax is a separate line.'

# 0. The check itself: a script that writes next to itself, in the fresh HOME or in TMPDIR is caught.
repo=$(new_repo selfcheck)
for stray in "$copy/review-routing/scripts/leak" "$fresh_home/.leak" "$TMPDIR/leak"; do
  listing before
  printf 'x\n' > "$stray"
  listing after
  assert_eq "$(changed_paths before after)" "$stray"
  rm "$stray"
done

# 1. escape-add.sh: one escape into the default folder, with the setting in the environment. Only the escapes folder.
repo=$(new_repo single)
listing before
REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes ESCAPE_DATE=2026-11-01 bash "$add" "$repo" src/billing wrong-result tax-in-total --body "$body_text" >/dev/null
assert_scope "escape-add" "$repo/.claude/mash-workbench/escapes/*"

# 2. escape-add.sh --batch: two blocks; the folder gains two escape files and the README.
repo=$(new_repo batch)
batch="$area/lists/batch.txt"
printf -- '---\narea: src/a\nclass: wrong-result\nslug: one\nsource: https://github.com/o/r/issues/1\n---\n\nFirst body.\n---8<---\n---\narea: src/a\nclass: missing-test\nslug: two\n---\n\nSecond body.\n' > "$batch"
listing before
REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes ESCAPE_DATE=2026-11-01 bash "$add" --batch - "$repo" < "$batch" >/dev/null
assert_scope "escape-add --batch" "$repo/.claude/mash-workbench/escapes/*"

# 3. escape-add.sh from a linked worktree: the files land in the main worktree's folder; the worktree stays untouched.
repo=$(new_repo linked)
mkdir -p "$repo/.claude"
git -C "$repo" worktree add --quiet -b w1 "$repo/.claude/worktrees/w1"
worktree="$repo/.claude/worktrees/w1"
listing before
REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes ESCAPE_DATE=2026-11-01 bash "$add" "$worktree" src/billing wrong-result from-worktree --body "$body_text" >/dev/null
assert_scope "escape-add from a linked worktree" "$repo/.claude/mash-workbench/escapes/*"
assert_file "$(find "$repo/.claude/mash-workbench/escapes" -name '*from-worktree*.md' | head -n 1)"

# 4. escape-add.sh with the folder outside the repository, inside the fresh HOME: only that folder changes.
repo=$(new_repo outside)
chosen="$fresh_home/.mash-workbench/o-r/escapes"
listing before
REVIEW_ROUTING_ESCAPES="$chosen" ESCAPE_DATE=2026-11-01 bash "$add" "$repo" src/billing wrong-result outside-folder --body "$body_text" >/dev/null
assert_scope "escape-add outside the repository" "$chosen/*"

# 5. escape-migrate.sh: an old ledger becomes files in the default folder; the old file stays and no setting changes.
repo=$(new_repo migrate)
mkdir -p "$repo/docs/mash"
printf -- '# Review escapes\n\n- 2026-10-11 · src/a · wrong-result · https://github.com/o/r/issues/1\n- 2026-10-12 · src/b · missing-test · https://github.com/o/r/issues/2\n' > "$repo/docs/mash/review-escapes.md"
git -C "$repo" add docs
git -C "$repo" commit --quiet -m "docs: old ledger"
listing before
bash "$migrate" "$repo" >/dev/null
assert_scope "escape-migrate" "$repo/.claude/mash-workbench/escapes/*"

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

# 7. review-log.sh add: reviews.log and the repository's info/exclude.
repo=$(new_repo log)
git -C "$repo" switch --quiet -c feat
printf 'a\n' > "$repo/a"
git -C "$repo" add a
git -C "$repo" commit --quiet -m "feat: a"
listing before
bash "$review_log" add "$repo" main HEAD >/dev/null
assert_scope "review-log add" "$repo/.claude/mash-workbench/reviews.log" "$repo/.git/info/exclude"

# 7b. review-log.sh reviewed and escapes-report.sh only read.
listing before
bash "$review_log" reviewed "$repo" HEAD
bash "$report" "$repo" >/dev/null
assert_no_change "review-log reviewed, escapes-report"

# 8. backlog-add.sh: the backlog file the setting names, and nothing else; the file is new, so its folder is too.
repo=$(new_repo backlog)
bash "$settings_script" set "$repo" backlog docs/mash/tooling-backlog.md --team >/dev/null
listing before
BACKLOG_DATE=2026-11-01 bash "$backlog_add" "$repo" script "Check the lockfile" "CI failed twice" >/dev/null
assert_scope "backlog-add" "$repo/docs/mash/tooling-backlog.md"
# 8b. From a linked worktree: the main worktree's file changes; the worktree stays untouched.
mkdir -p "$repo/.claude"
git -C "$repo" worktree add --quiet -b w1 "$repo/.claude/worktrees/w1"
listing before
BACKLOG_DATE=2026-11-01 bash "$backlog_add" "$repo/.claude/worktrees/w1" hook "Block force pushes" "twice" >/dev/null
assert_scope "backlog-add from a linked worktree" "$repo/docs/mash/tooling-backlog.md"
# 8c. An old backlog with no setting and no owner line: the file is rewritten in place (the owner line, the entry),
# and the temporary copy next to it is gone.
repo=$(new_repo backlogold)
mkdir -p "$repo/docs"; printf '# Tooling backlog\n\n' > "$repo/docs/tooling-backlog.md"
listing before
BACKLOG_DATE=2026-11-01 bash "$backlog_add" "$repo" script "Check the lockfile" "CI failed twice" >/dev/null 2>&1
assert_scope "backlog-add to an old backlog" "$repo/docs/tooling-backlog.md"
assert_contains "$(cat "$repo/docs/tooling-backlog.md")" "repo: local/"
# 8d. backlog-stale.sh only reads.
listing before
BACKLOG_TODAY=2027-01-01 bash "$backlog_stale" "$repo" > "$area/lists/stale.out"
assert_contains "$(cat "$area/lists/stale.out")" "Check the lockfile"
assert_no_change "backlog-stale"

# 9. The router reads a config and prints; it changes nothing, in every mode. python.sh keeps Python from writing a
# __pycache__ next to the route_*.py files it imports.
repo=$(new_repo router)
mkdir -p "$repo/.claude" "$repo/src/billing"
printf '[[routes]]\npattern = "^src/billing/"\nreviewers = ["billing-reviewer"]\n\n[[expect]]\npath = "src/billing/a.py"\nreviewers = ["billing-reviewer"]\n' > "$repo/.claude/reviewers.toml"
mkdir -p "$repo/.claude/agents"; printf -- '---\nname: billing-reviewer\nmodel: sonnet\n---\nReview billing.\n' > "$repo/.claude/agents/billing-reviewer.md"
printf 'x = 1\n' > "$repo/src/billing/a.py"
git -C "$repo" add .
git -C "$repo" commit --quiet -m "feat: billing"
listing before
(
  cd "$repo"
  bash "$python_finder" "$router" --paths src/billing/a.py
  bash "$python_finder" "$router" HEAD~1..HEAD --models
  bash "$python_finder" "$router" HEAD~1..HEAD --explain
  bash "$python_finder" "$router" --check
) > "$area/lists/router.out" 2>&1
assert_contains "$(cat "$area/lists/router.out")" "billing-reviewer"
assert_contains "$(cat "$area/lists/router.out")" "expectations hold"
assert_no_change "router"
assert_eq "$(find "$copy" -name __pycache__)" ""

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

# 11. permission-rules.sh (both plugins' copies) reads the settings.local.json files and the worktree list and prints
# rules: nothing changes.
repo=$(new_repo rules)
mkdir -p "$repo/.claude"
printf '{"permissions": {"allow": ["Bash(bash */review-routing/*add-reviewer/escape-add.sh*)"]}}\n' > "$repo/.claude/settings.local.json"
listing before
bash "$copy/review-routing/skills/review-changes/permission-rules.sh" "$repo" > "$area/lists/rules.out"
bash "$copy/mash-workbench/skills/scout/permission-rules.sh" "$repo" >> "$area/lists/rules.out"
assert_contains "$(cat "$area/lists/rules.out")" "remove:"
assert_contains "$(cat "$area/lists/rules.out")" "backlog-add.sh *)"
assert_no_change "permission-rules"

# 12. The reviewer-guard hook reads its input, the routing config and git output, and never writes: a command it
# refuses (exit 2) and a command it lets pass (exit 0) both change nothing.
repo=$(new_repo guard)
guard_input() { printf '{"tool_name": "Bash", "cwd": "%s", "agent_type": "review-routing:change-reviewer", "tool_input": {"command": "%s"}}\n' "$repo" "$1"; }
listing before
status=0
guard_input "git commit --allow-empty -m x" | CLAUDE_PLUGIN_ROOT="$copy/review-routing" bash "$python_finder" --missing-ok "$guard" > /dev/null 2>&1 || status=$?
assert_eq "$status" "2"
status=0
guard_input "git status" | CLAUDE_PLUGIN_ROOT="$copy/review-routing" bash "$python_finder" --missing-ok "$guard" > /dev/null 2>&1 || status=$?
assert_eq "$status" "0"
assert_no_change "reviewer-guard hook"

# 13. plugin-current.sh only reads.
listing before
bash "$copy/review-routing/scripts/plugin-current.sh"
assert_no_change "plugin-current"
echo "write scope: ok"
