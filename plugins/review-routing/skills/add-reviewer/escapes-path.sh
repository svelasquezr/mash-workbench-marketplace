#!/usr/bin/env bash
# Print the review escapes this project keeps, as an absolute path. The answer is the same from every worktree:
# the setting and the old ledgers are read from the main worktree (scripts/mash-settings.sh), never from <repo-root>.
#   The escapes setting (mash-settings.sh get <repo-root> escapes: REVIEW_ROUTING_ESCAPES, then
#   <main>/.claude/mash-workbench/settings.local, then settings): that path, a relative one from the main worktree;
#   "off": the project keeps none.
#   Not set: docs/mash/review-escapes.md in the main worktree when it exists, else the older docs/review-escapes.md;
#   both are the old one-line-per-escape format, so stderr names the old file in use.
# Exit 0 with the path; 3 when nothing has been chosen yet (not set and no old file), so nothing is created before
# the user says where; 4 when it is off; 5 when the repository has no main worktree to read (bare, or a linked
# worktree of a --separate-git-dir repository) and no absolute path is set.
# Outside a git repository, <repo-root> stands in for the main worktree and only REVIEW_ROUTING_ESCAPES is read
# (no settings files). Until escape-add.sh writes one file per escape, the path may name a file.
set -euo pipefail
usage="usage: escapes-path.sh <repo-root>"
[[ $# -eq 1 && -d "$1" ]] || { echo "$usage" >&2; exit 2; }
root="$(cd "$1" && pwd -P)"
settings="$(dirname "${BASH_SOURCE[0]}")/../../scripts/mash-settings.sh"
is_absolute() { [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]; }
main_status=0
main=$(bash "$settings" main-worktree "$root" 2>/dev/null) || main_status=$?
case "$main_status" in
  0) ;;
  2) main="$root" ;;  # not a git repository: only the environment variable and <repo-root> can answer
  5) main="" ;;
  *) exit "$main_status" ;;
esac
status=0
if (( main_status == 2 )); then
  choice="${REVIEW_ROUTING_ESCAPES:-}"
  [[ -n "$choice" ]] || status=3
else
  choice=$(bash "$settings" get "$root" escapes) || status=$?
fi
case "$status" in
  0) ;;
  3) ;;
  *) exit "$status" ;;
esac
if (( status == 0 )); then
  if [[ "$choice" == off ]]; then exit 4; fi
  if ! is_absolute "$choice"; then
    if [[ -z "$main" ]]; then
      echo "escapes-path: the escapes setting is relative, but no main worktree was found: set it to an absolute path" >&2
      exit 5
    fi
    choice="$main/$choice"
  fi
  if [[ -n "$main" ]]; then
    for other in docs/mash/review-escapes.md docs/review-escapes.md; do
      if [[ ! -e "$choice" && -f "$main/$other" ]]; then
        echo "escapes-path: the escapes setting names a new path, but $other already holds escapes; the report will not count them. Move it there with git mv, or point the setting at it." >&2
        break
      fi
    done
  fi
  printf '%s\n' "$choice"
  exit 0
fi
if [[ -f "$main/docs/mash/review-escapes.md" && -f "$main/docs/review-escapes.md" ]]; then
  echo "escapes-path: both docs/mash/review-escapes.md and docs/review-escapes.md exist; using the first. Merge the entries and remove the other so the report counts them all." >&2
fi
for candidate in docs/mash/review-escapes.md docs/review-escapes.md; do
  if [[ -f "$main/$candidate" ]]; then
    echo "escapes-path: old ledger file in use: $candidate" >&2
    printf '%s\n' "$main/$candidate"
    exit 0
  fi
done
exit 3
