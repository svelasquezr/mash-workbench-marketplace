# shellcheck shell=bash
# review-log.sh: the log of reviewed ranges that lets record-escape tell whether a commit passed a review, also after a
# squash or rebase merge and after the reviewed branch and its commits are gone.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
log_script="$PWD/plugins/review-routing/skills/review-changes/review-log.sh"
# The path checks refuse /tmp, so the fixtures live under $HOME (never under /tmp).
fixture=$(mktemp -d "$HOME/.review-log-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$fixture"
isolate_git_config

# new_repo <name>: a repository with a file "base" committed on main; .claude/worktrees/ is excluded as the plan says.
new_repo() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  mkdir -p "$folder/.git/info"
  echo ".claude/worktrees/" >> "$folder/.git/info/exclude"
  echo base > "$folder/base"
  git -C "$folder" add base
  git -C "$folder" commit --quiet -m "chore: base"
  (cd "$folder" && pwd -P)
}
# commit_file <repo> <file> <content> <message>: commit a new file; prints nothing.
commit_file() {
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit --quiet -m "$4"
}
reviewed() { bash "$in_root_script" "$log_script" reviewed "$@"; }

# 1. reviewed: inside the range yes; the base, an earlier commit, a later commit and another branch no.
repo=$(new_repo range)
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
first=$(git -C "$repo" rev-parse HEAD)
commit_file "$repo" b b1 "feat: b"
head=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$head"
assert_eq "$captured_exit_code" "0"
log="$repo/.claude/mash-workbench/reviews.log"
assert_file "$log"
assert_eq "$(wc -l < "$log" | tr -d ' ')" "1"
read -r date logged_base logged_head range_id commit_ids < "$log"
assert_eq "$logged_base" "$base"
assert_eq "$logged_head" "$head"
[[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "  bad date: $date"; exit 1; }
[[ "$range_id" =~ ^[0-9a-f]{40}$ ]] || { echo "  bad range patch-id: $range_id"; exit 1; }
assert_eq "$(printf '%s\n' "$commit_ids" | tr ',' '\n' | wc -l | tr -d ' ')" "2"
run_capturing reviewed "$repo" "$first"; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$head"; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" HEAD; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$base"; assert_eq "$captured_exit_code" "1"
commit_file "$repo" c c1 "feat: c, after the review"
run_capturing reviewed "$repo" HEAD; assert_eq "$captured_exit_code" "1"
git -C "$repo" switch --quiet main
git -C "$repo" switch --quiet -c other
commit_file "$repo" o o1 "feat: other"
run_capturing reviewed "$repo" HEAD; assert_eq "$captured_exit_code" "1"
# A second add of the same range writes no second line.
bash "$in_root_script" "$log_script" add "$repo" "$base" "$head" >/dev/null
assert_eq "$(wc -l < "$log" | tr -d ' ')" "1"
# Usage errors.
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base"; assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$base"; assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" not-a-commit; assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$log_script" reviewed "$repo" not-a-commit; assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$log_script" nonsense "$repo"; assert_eq "$captured_exit_code" "2"
# A repository with no log answers "not reviewed".
empty=$(new_repo nolog)
run_capturing reviewed "$empty" HEAD; assert_eq "$captured_exit_code" "1"
assert_eq "$captured_output" ""
[[ ! -e "$empty/.claude/mash-workbench" ]] || { echo "  reviewed created the home folder"; exit 1; }

# 2. Squash merge, then the branch and its commits are gone: the patch-id of the range still matches.
repo=$(new_repo squash)
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
commit_file "$repo" b b1 "feat: b"
head=$(git -C "$repo" rev-parse HEAD)
bash "$in_root_script" "$log_script" add "$repo" "$base" "$head" >/dev/null
git -C "$repo" switch --quiet main
commit_file "$repo" unrelated u1 "chore: unrelated work on main"
git -C "$repo" merge --squash feat >/dev/null 2>&1
git -C "$repo" commit --quiet -m "feat: a and b (#1)"
squash=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" branch --quiet -D feat
git -C "$repo" reflog expire --expire=now --all
git -C "$repo" gc --quiet --prune=now
if git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null; then echo "  the reviewed head still exists after gc"; exit 1; fi
run_capturing reviewed "$repo" "$squash"; assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""
run_capturing reviewed "$repo" HEAD~1; assert_eq "$captured_exit_code" "1"

# 3. Rebase merge or cherry-pick: a commit with the same diff and another id.
repo=$(new_repo rebase)
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
first=$(git -C "$repo" rev-parse HEAD)
commit_file "$repo" b b1 "feat: b"
head=$(git -C "$repo" rev-parse HEAD)
bash "$in_root_script" "$log_script" add "$repo" "$base" "$head" >/dev/null
git -C "$repo" switch --quiet main
commit_file "$repo" unrelated u1 "chore: unrelated work on main"
git -C "$repo" cherry-pick "$first" >/dev/null
picked=$(git -C "$repo" rev-parse HEAD)
[[ "$picked" != "$first" ]] || { echo "  the cherry-pick kept the id"; exit 1; }
run_capturing reviewed "$repo" "$picked"; assert_eq "$captured_exit_code" "0"
# A commit that was not reviewed still answers 1 (also on main, where the reviewed commits are not ancestors).
commit_file "$repo" z z1 "feat: not reviewed"
run_capturing reviewed "$repo" HEAD; assert_eq "$captured_exit_code" "1"

# 4. add from a linked worktree: the log lands in the main worktree, and both worktrees stay clean.
repo=$(new_repo linked)
git -C "$repo" worktree add --quiet .claude/worktrees/w -b w
linked="$repo/.claude/worktrees/w"
base=$(git -C "$linked" rev-parse HEAD)
commit_file "$linked" a a1 "feat: a"
run_capturing bash "$in_root_script" "$log_script" add "$linked" "$base" HEAD
assert_eq "$captured_exit_code" "0"
assert_file "$repo/.claude/mash-workbench/reviews.log"
[[ ! -e "$linked/.claude/mash-workbench" ]] || { echo "  wrote into the linked worktree"; exit 1; }
assert_eq "$(git -C "$linked" status --porcelain)" ""
assert_eq "$(git -C "$repo" status --porcelain)" ""
assert_contains "$(cat "$repo/.git/info/exclude")" ".claude/mash-workbench/reviews.log"
# The exclude line is written once, however often add runs.
commit_file "$linked" b b1 "feat: b"
bash "$in_root_script" "$log_script" add "$linked" "$base" HEAD >/dev/null
assert_eq "$(grep -c -x '.claude/mash-workbench/reviews.log' "$repo/.git/info/exclude")" "1"
run_capturing reviewed "$linked" HEAD; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$(git -C "$linked" rev-parse HEAD)"; assert_eq "$captured_exit_code" "0"

# 5. A line whose SHAs no longer exist is not an error, and it matches nothing by id.
repo=$(new_repo stale)
mkdir -p "$repo/.claude/mash-workbench"
zero=0000000000000000000000000000000000000000
printf '2026-01-01 %s %s %s %s,%s\r\n' "$zero" "1111111111111111111111111111111111111111" \
  "2222222222222222222222222222222222222222" "3333333333333333333333333333333333333333" \
  "4444444444444444444444444444444444444444" > "$repo/.claude/mash-workbench/reviews.log"
printf 'garbage line\n\n' >> "$repo/.claude/mash-workbench/reviews.log"
# The exclude line that add writes: without it the log is not read (tests/test_consumer_safety.sh, case 2).
grep -qx '.claude/mash-workbench/reviews.log' "$repo/.git/info/exclude" 2>/dev/null || printf '.claude/mash-workbench/reviews.log\n' >> "$repo/.git/info/exclude"
run_capturing reviewed "$repo" HEAD
assert_eq "$captured_exit_code" "1"
assert_eq "$captured_output" ""

# Not in a repository: a usage error, nothing written.
plain=$(mktemp -d "$fixture/plain.XXXXXX")
run_capturing bash "$in_root_script" "$log_script" reviewed "$plain" HEAD
assert_eq "$captured_exit_code" "2"

# 6. The ids do not depend on the user's git config: color.ui=always, an external diff and diff.noprefix are set, and a
# squash-merged reviewed branch still matches. No id is "-" for a non-empty diff.
repo=$(new_repo config)
printf '#!/bin/sh\nexit 1\n' > "$fixture/failing-diff"; chmod +x "$fixture/failing-diff"
git config --global color.ui always
git config --global diff.external "$fixture/failing-diff"
git config --global diff.noprefix true
git config --global diff.renames true
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
commit_file "$repo" b b1 "feat: b"
head=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$head"
assert_eq "$captured_exit_code" "0"
read -r _ _ _ range_id commit_ids < "$repo/.claude/mash-workbench/reviews.log"
[[ "$range_id" =~ ^[0-9a-f]{40}$ ]] || { echo "  bad range patch-id under user config: $range_id"; exit 1; }
assert_not_contains "$commit_ids" "-"
git -C "$repo" switch --quiet main
git -C "$repo" merge --squash feat >/dev/null 2>&1
git -C "$repo" commit --quiet -m "feat: a and b (#2)"
squash=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" branch --quiet -D feat
git -C "$repo" reflog expire --expire=now --all
git -C "$repo" gc --quiet --prune=now
run_capturing reviewed "$repo" "$squash"; assert_eq "$captured_exit_code" "0"
# The same answer comes with a plain config.
git config --global --unset color.ui
git config --global --unset diff.external
git config --global --unset diff.noprefix
git config --global --unset diff.renames
run_capturing reviewed "$repo" "$squash"; assert_eq "$captured_exit_code" "0"

# 7. add refuses a base that is not an ancestor of the head, and a range with no changes. Nothing is logged.
repo=$(new_repo refuse)
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
head=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet main
commit_file "$repo" m m1 "chore: on main"
run_capturing bash "$in_root_script" "$log_script" add "$repo" main "$head"; assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "ancestor"
git -C "$repo" switch --quiet feat
git -C "$repo" revert --no-edit HEAD >/dev/null
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD; assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "nothing to log: the range has no changes"
[[ ! -e "$repo/.claude/mash-workbench/reviews.log" ]] || { echo "  a refused add wrote the log"; exit 1; }

# 8. A merge commit inside a logged range: its own commits and the merge are reviewed; the base is not.
repo=$(new_repo merge)
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" a a1 "feat: a"
git -C "$repo" switch --quiet -c side "$base"
commit_file "$repo" s s1 "feat: side"
side=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet feat
git -C "$repo" merge --quiet --no-ff side -m "merge side" >/dev/null 2>&1
head=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$head"; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$head"; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$side"; assert_eq "$captured_exit_code" "0"
run_capturing reviewed "$repo" "$base"; assert_eq "$captured_exit_code" "1"

# 9. Exit 5: a linked worktree of a --separate-git-dir repository has no findable main worktree.
work="$fixture/sep-work"
git init --quiet --separate-git-dir="$fixture/sep-gitdir" "$work"
git -C "$work" commit --quiet --allow-empty -m "chore: base"
git -C "$work" worktree add --quiet .claude/worktrees/w -b w
run_capturing bash "$in_root_script" "$log_script" add "$work/.claude/worktrees/w" HEAD HEAD
assert_eq "$captured_exit_code" "5"
assert_contains "$captured_output" "main worktree not found"
run_capturing bash "$in_root_script" "$log_script" reviewed "$work/.claude/worktrees/w" HEAD
assert_eq "$captured_exit_code" "5"

# 10. Submodule: the exclude line goes to the submodule's own info/exclude under the superproject's .git/modules.
inner=$(new_repo inner)
super=$(new_repo super)
git -C "$super" -c protocol.file.allow=always submodule add --quiet "$inner" sub >/dev/null 2>&1
sub="$super/sub"
base=$(git -C "$sub" rev-parse HEAD)
commit_file "$sub" a a1 "feat: a"
run_capturing bash "$in_root_script" "$log_script" add "$sub" "$base" HEAD
assert_eq "$captured_exit_code" "0"
assert_file "$sub/.claude/mash-workbench/reviews.log"
assert_contains "$(cat "$super/.git/modules/sub/info/exclude")" ".claude/mash-workbench/reviews.log"
assert_eq "$(git -C "$sub" status --porcelain)" ""

# 11. Porcelain diff settings about submodules and paths do not change any id. A reviewed branch that bumps a
# submodule and changes a file is squash-merged, then gc runs: reviewed still returns 0. A range that only bumps the
# submodule logs real ids.
git config --global diff.submodule log
git config --global diff.ignoreSubmodules all
git config --global diff.relative true
inner=$(new_repo inner2)
repo=$(new_repo subbump)
git -C "$repo" -c protocol.file.allow=always submodule add --quiet "$inner" vendor >/dev/null 2>&1
git -C "$repo" commit --quiet -m "chore: add submodule"
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$inner" i i1 "feat: new in the submodule"
git -C "$repo/vendor" pull --quiet >/dev/null 2>&1
git -C "$repo" add vendor
git -C "$repo" commit --quiet -m "chore: bump the submodule"
bump_only=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$bump_only"
assert_eq "$captured_exit_code" "0"
read -r _ _ _ range_id commit_ids < "$repo/.claude/mash-workbench/reviews.log"
[[ "$range_id" =~ ^[0-9a-f]{40}$ ]] || { echo "  bad range id for a submodule-only range: $range_id"; exit 1; }
# A range of one commit has the id of that commit.
assert_eq "$range_id" "$commit_ids"
commit_file "$repo" a a1 "feat: a"
head=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" "$head"
assert_eq "$captured_exit_code" "0"
git -C "$repo" switch --quiet main
git -C "$repo" merge --squash feat >/dev/null 2>&1
git -C "$repo" commit --quiet -m "feat: bump and a (#3)"
squash=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" branch --quiet -D feat
git -C "$repo" reflog expire --expire=now --all
git -C "$repo" gc --quiet --prune=now
run_capturing reviewed "$repo" "$squash"; assert_eq "$captured_exit_code" "0"

# diff.relative with a repo-root that is a subdirectory: the ids cover the whole change, so the squash still matches.
repo=$(new_repo relative)
mkdir -p "$repo/one" "$repo/two"
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch --quiet -c feat
commit_file "$repo" one/x x1 "feat: x"
commit_file "$repo" two/y y1 "feat: y"
head=$(git -C "$repo" rev-parse HEAD)
run_capturing bash "$in_root_script" "$log_script" add "$repo/one" "$base" "$head"; assert_eq "$captured_exit_code" "0"
git -C "$repo" switch --quiet main
git -C "$repo" merge --squash feat >/dev/null 2>&1
git -C "$repo" commit --quiet -m "feat: x and y (#4)"
squash=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" branch --quiet -D feat
git -C "$repo" reflog expire --expire=now --all
git -C "$repo" gc --quiet --prune=now
run_capturing reviewed "$repo/one" "$squash"; assert_eq "$captured_exit_code" "0"
git config --global --unset diff.submodule
git config --global --unset diff.ignoreSubmodules
git config --global --unset diff.relative

# 12. A failing git patch-id: add exits 6 and logs nothing (the stub passes every other git command through).
repo=$(new_repo stub)
base=$(git -C "$repo" rev-parse HEAD)
commit_file "$repo" a a1 "feat: a"
mkdir -p "$fixture/stubbin"
# The stub counts the calls of git patch-id, also after -C <dir> (in $STUB_COUNT): the call number STUB_FAIL_CALL fails, the call number
# STUB_GARBAGE_CALL prints a line that is no patch-id; every other call, and every other git command, is real git.
# shellcheck disable=SC2016  # $1, $n and $@ are for the stub script, not for this one
printf '%s\n' '#!/bin/sh' 'sub=$1; if [ "$1" = -C ]; then sub=$3; fi' 'if [ "$sub" = patch-id ]; then' \
  '  n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_COUNT"' \
  '  if [ "$n" = "${STUB_FAIL_CALL:-}" ]; then cat >/dev/null; exit 1; fi' \
  '  if [ "$n" = "${STUB_GARBAGE_CALL:-}" ]; then cat >/dev/null; echo "zzzz yyyy"; exit 0; fi' \
  'fi' "exec \"$(command -v git)\" \"\$@\"" > "$fixture/stubbin/git"
chmod +x "$fixture/stubbin/git"
# stubbed <fail-call> <garbage-call> <command...>: run with a fresh call counter.
stubbed() {
  local fail=$1 garbage=$2
  shift 2
  rm -f "$fixture/stub-count"
  env PATH="$fixture/stubbin:$PATH" STUB_COUNT="$fixture/stub-count" STUB_FAIL_CALL="$fail" STUB_GARBAGE_CALL="$garbage" "$@"
}
# The range id fails (call 1): exit 6, nothing logged.
run_capturing stubbed 1 0 bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "could not compute the patch-id"
[[ ! -e "$repo/.claude/mash-workbench/reviews.log" ]] || { echo "  a failed add wrote the log"; exit 1; }
# A per-commit id fails (call 2, after the range id worked): the log gains exactly one line of five fields.
commit_file "$repo" b b1 "feat: b"
run_capturing stubbed 2 0 bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD
assert_eq "$captured_exit_code" "0"
assert_eq "$(wc -l < "$repo/.claude/mash-workbench/reviews.log" | tr -d ' ')" "1"
assert_eq "$(awk '{ print NF }' "$repo/.claude/mash-workbench/reviews.log")" "5"
assert_not_contains "$(cat "$repo/.claude/mash-workbench/reviews.log")" "zzzz"
rm "$repo/.claude/mash-workbench/reviews.log"
# A per-commit id that is no patch-id (call 2 prints garbage): the guard refuses the record and writes nothing.
run_capturing stubbed 0 2 bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "not one line of five fields"
[[ ! -e "$repo/.claude/mash-workbench/reviews.log" ]] || { echo "  the guard let a broken record through"; exit 1; }
# reviewed with a failing patch-id prints nothing and still answers by the range (rule a).
bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD >/dev/null
run_capturing stubbed 1 0 bash "$in_root_script" "$log_script" reviewed "$repo" HEAD
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""

# A repository can commit symbolic links. reviews.log, or the home folder, as a link would send the appended line to
# another file: refused with exit 6, and the other file stays as it was.
repo=$(new_repo links)
base=$(git -C "$repo" rev-parse HEAD)
commit_file "$repo" a a1 "feat: a"
printf 'keep\n' > "$fixture/outside-target"
mkdir -p "$repo/.claude/mash-workbench"
ln -s "$fixture/outside-target" "$repo/.claude/mash-workbench/reviews.log"
for arguments in "add $repo $base HEAD" "reviewed $repo HEAD"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing bash "$in_root_script" "$log_script" $arguments
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "symbolic link"
done
rm -r "$repo/.claude/mash-workbench"; mkdir -p "$fixture/outside-home"
ln -s "$fixture/outside-home" "$repo/.claude/mash-workbench"
run_capturing bash "$in_root_script" "$log_script" add "$repo" "$base" HEAD
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
assert_eq "$(cat "$fixture/outside-target")" "keep"
assert_eq "$(find "$fixture/outside-home" -type f | wc -l | tr -d ' ')" "0"
# A revision that starts with "-" is not read as a git option.
rm "$repo/.claude/mash-workbench"
for option in --all -q --git-dir=/x; do
  run_capturing bash "$in_root_script" "$log_script" add "$repo" "$option" HEAD
  assert_eq "$captured_exit_code" "2"
  assert_contains "$captured_output" "not a commit"
  run_capturing bash "$in_root_script" "$log_script" reviewed "$repo" "$option"
  assert_eq "$captured_exit_code" "2"
done
