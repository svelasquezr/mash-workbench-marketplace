#!/usr/bin/env bash
set -euo pipefail
# The log of reviewed ranges: <main worktree>/.claude/mash-workbench/reviews.log (scripts/mash-settings.sh home). It
# answers one question for the record-escape skill: did a review pass the code of this commit? The log belongs to this
# clone and is always excluded (.claude/mash-workbench/reviews.log in the repository's info/exclude), so nothing
# reaches a commit or a pull request. Every worktree reads and writes the main worktree's log.
#
# Usage:
#   review-log.sh add <repo-root> <base> <head>
#       Append one line, after a review of <base>..<head> where every reviewer said SAFE TO LAND:
#         <YYYY-MM-DD> <base-sha> <head-sha> <range-patch-id> <commit-patch-id>,<commit-patch-id>,...
#       The patch-ids come from git patch-id --stable: one for the whole range (the diff of <base> and <head>), one for
#       each non-merge commit. For a "<default>...HEAD" range, <base> is the merge base. The base must be an ancestor
#       of the head, and the range must change something: otherwise nothing is logged (exit 2). The same base and
#       head are logged once. Every diff is made with git diff-tree (plumbing) from the main worktree, with fixed options
#       (no color, no external diff, no text conversion, no rename detection, a/ and b/ prefixes, --binary, submodule
#       changes as Subproject lines), so the ids do not depend on the user's git config. The range id of a one-commit
#       range is that commit's own id.
#   review-log.sh reviewed <repo-root> <commit>
#       Exit 0 when a logged line matches the commit, else 1. A line matches when
#         a. its base and head still exist, the commit is an ancestor of the head and not of the base; or
#         b. the commit's patch-id is the line's range patch-id (a squash merge of the reviewed branch); or
#         c. the commit's patch-id is one of the line's commit patch-ids (a rebase merge or a cherry-pick).
#       A patch-id depends only on the diff, so b and c still match after the branch is deleted and git gc has removed
#       its commits. Limits: a squash merge that needed conflict fixes has another diff and does not match, and
#       --stable ignores whitespace, so a change that differs only in whitespace has the same patch-id. When it does
#       not match, the caller asks the user. Another limit: a .gitattributes change on the reviewed branch that
#       changes whether a file counts as binary changes how its diff is written, so a later squash merge misses.
#
# Exit codes: 0 added, already logged, or reviewed; 1 not reviewed (reviewed only: no log, or no line matches);
# 2 usage error, a commit that does not exist, a base that is not an ancestor of the head, a range with no changes,
# or <repo-root> not in a git repository; 5 no main worktree (bare repository, or a linked worktree of a
# --separate-git-dir repository); 6 a patch-id could not be computed, or the record is not one line of five fields
# (nothing logged), or refused: the home folder or reviews.log is a symbolic link (a repository can commit one, and the
# line would go where it points), or this copy of the plugin is an old version in Claude Code's plugin cache
# (scripts/plugin-current.sh).
# Plain bash 3.2 (macOS) and Git Bash: no python3, no mapfile.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bash "$here/../../scripts/plugin-current.sh" < /dev/null || exit $?
settings=$(cd "$here/../../scripts" && pwd -P)/mash-settings.sh
usage_text="usage: review-log.sh add <repo-root> <base> <head>
       review-log.sh reviewed <repo-root> <commit>"
refuse() { echo "review-log: $*" >&2; echo "$usage_text" >&2; exit 2; }
log_entry=".claude/mash-workbench/reviews.log"
# Options that make a diff the same on every machine, whatever the user's git config says.
dflags=(-c core.quotePath=false -c diff.renames=false -c diff.algorithm=myers -c diff.context=3 -c diff.noprefix=false
  -c diff.mnemonicPrefix=false -c color.ui=never -c diff.colorMoved=false -c diff.wsErrorHighlight=none)
dopts=(--no-color --no-ext-diff --no-textconv --no-renames --binary --ignore-submodules=none --src-prefix=a/ --dst-prefix=b/ -U3)

[[ $# -ge 2 ]] || refuse "arguments needed"
mode=$1
root=$2
[[ -d "$root" ]] || refuse "no such repository root: $root"
case "$mode" in
  add) [[ $# -eq 4 ]] || refuse "add needs <repo-root> <base> <head>" ;;
  reviewed) [[ $# -eq 3 ]] || refuse "reviewed needs <repo-root> <commit>" ;;
  *) refuse "unknown command: $mode" ;;
esac
root=$(cd "$root" && pwd -P)
status=0
main=$(bash "$settings" main-worktree "$root" 2>/dev/null) || status=$?
if ((status != 0)); then
  echo "review-log: $(bash "$settings" main-worktree "$root" 2>&1 >/dev/null || true)" >&2
  exit "$status"
fi
# The home folder must be a real folder in the main worktree, and the log a real file.
bash "$settings" home "$root" >/dev/null || exit $?
log="$main/$log_entry"
if [[ -L "$log" ]]; then echo "review-log: $log is a symbolic link: nothing read or logged" >&2; exit 6; fi

# commit_of <rev>: the full commit id, or exit 2.
commit_of() {
  local id
  [[ "$1" != -* ]] || refuse "not a commit: $1"
  id=$(git -C "$root" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null) || refuse "not a commit: $1"
  printf '%s' "${id%$'\r'}"
}
# first_field: stdin to the first word of the first line, or "-" when there is none (an empty diff has no patch-id).
first_field() { awk 'NR == 1 { print $1; found = 1 } END { if (!found) print "-" }'; }
# commit_id <commit>: the patch-id of one commit's own diff ("-" for a merge commit or an empty commit).
commit_id() {
  local id
  id=$(tree_diff --root "$1" | git patch-id --stable | first_field) || id="-"
  printf '%s\n' "$id"
}
# tree_diff <diff-tree arguments>: plumbing only, run from the top level, so no porcelain setting (diff.submodule,
# diff.ignoreSubmodules, diff.relative, ...) changes the diff that a patch-id is made from.
tree_diff() { git "${dflags[@]}" -C "$main" diff-tree -p -r --no-commit-id "${dopts[@]}" "$@"; }

if [[ "$mode" == add ]]; then
  base=$(commit_of "$3")
  head=$(commit_of "$4")
  [[ "$base" != "$head" ]] || refuse "nothing to log: the range is empty (base and head are the same commit)"
  git -C "$root" merge-base --is-ancestor "$base" "$head" 2>/dev/null || refuse "the base must be an ancestor of the head"
  if [[ -z "$(git "${dflags[@]}" -C "$main" diff-tree -r --raw "$base" "$head")" ]]; then
    refuse "nothing to log: the range has no changes"
  fi
  if [[ -f "$log" ]] && awk -v base="$base" -v head="$head" '{ sub(/\r$/, "") } $2 == base && $3 == head { found = 1 } END { exit !found }' "$log"; then
    echo "already logged: $(printf '%s' "$base" | cut -c1-9)..$(printf '%s' "$head" | cut -c1-9)"
    exit 0
  fi
  range_id=$(tree_diff "$base" "$head" | git patch-id --stable | first_field) || range_id="-"
  if [[ ! "$range_id" =~ ^[0-9a-f]{40,64}$ ]]; then
    echo "review-log: could not compute the patch-id of the range diff; nothing logged" >&2
    exit 6
  fi
  commit_ids=""
  for sha in $(git -C "$root" rev-list --reverse --no-merges "$base..$head"); do
    id=$(commit_id "$sha")
    if [[ "$id" == "-" ]]; then continue; fi  # an empty commit has no diff
    commit_ids="$commit_ids${commit_ids:+,}$id"
  done
  [[ -n "$commit_ids" ]] || commit_ids="-"
  # The record is one line of exactly five fields, or nothing is written: a broken line would stay in the log.
  record="$(date -u +%F) $base $head $range_id $commit_ids"
  hex='[0-9a-f]{40,64}'
  if [[ ! "$record" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ $hex\ $hex\ $hex\ (-|$hex(,$hex)*)$ ]]; then
    echo "review-log: the log record is not one line of five fields; nothing logged" >&2
    exit 6
  fi
  # The exclude line comes first, so the log never shows up as untracked, even for a moment. Always the common git
  # dir's exclude file: in submodules and --separate-git-dir repositories, <main>/.git is a file.
  common=$(cd "$main" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  exclude="$common/info/exclude"
  mkdir -p "$common/info"
  if ! { [[ -f "$exclude" ]] && LINE="$log_entry" awk '{ sub(/\r$/, "") } $0 == ENVIRON["LINE"] { found = 1 } END { exit !found }' "$exclude"; }; then
    if [[ -s "$exclude" && -n "$(tail -c1 "$exclude")" ]]; then printf '\n' >> "$exclude"; fi
    printf '%s\n' "$log_entry" >> "$exclude"
  fi
  mkdir -p "$main/.claude/mash-workbench"
  # One short line per append: appends of one line do not interleave, so two sessions can log at once.
  printf '%s\n' "$record" >> "$log"
  echo "logged: $(printf '%s' "$base" | cut -c1-9)..$(printf '%s' "$head" | cut -c1-9)"
  exit 0
fi

# reviewed
commit=$(commit_of "$3")
[[ -f "$log" && -r "$log" ]] || exit 1
# b and c, over the whole log with the commit's own patch-id (computed once).
own_id=$(commit_id "$commit")
if [[ "$own_id" != "-" ]] && ID="$own_id" awk '
  { sub(/\r$/, "") }
  NF >= 5 && ($4 == ENVIRON["ID"] || index("," $5 ",", "," ENVIRON["ID"] ",") > 0) { found = 1 }
  END { exit !found }' "$log"; then
  exit 0
fi
# a. The commit lies in a logged range whose commits still exist.
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  base="" head="" commit_ids=""
  read -r _ base head _ commit_ids _ <<< "$line"
  [[ -n "$commit_ids" ]] || continue
  # Only commit ids reach git: a line that someone wrote by hand could hold anything.
  [[ "$base" =~ ^[0-9a-f]{40,64}$ && "$head" =~ ^[0-9a-f]{40,64}$ ]] || continue
  if git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null && git -C "$root" cat-file -e "$head^{commit}" 2>/dev/null \
    && git -C "$root" merge-base --is-ancestor "$commit" "$head" 2>/dev/null \
    && ! git -C "$root" merge-base --is-ancestor "$commit" "$base" 2>/dev/null; then
    exit 0
  fi
done < "$log"
exit 1
