#!/usr/bin/env bash
# Print the review escapes this project keeps, as an absolute path. The answer is the same from every worktree:
# the setting and the old ledgers are read from the main worktree (scripts/mash-settings.sh), never from <repo-root>.
#   The escapes setting (mash-settings.sh path <repo-root> escapes: REVIEW_ROUTING_ESCAPES, then
#   <main>/.claude/mash-workbench/settings.local, then settings): that path, a relative one from the main worktree;
#   "off": the project keeps none.
#   Not set: docs/mash/review-escapes.md in the main worktree when it exists, else the older docs/review-escapes.md;
#   both are the old one-line-per-escape format, so stderr names the old file and points at escape-migrate.sh.
# The path is normally the escapes folder (one file per escape). It is a file when it names an old ledger: the fallback
# above, or an escapes setting that still names a file. escape-add.sh then refuses to record until it is migrated.
# Exit 0 with the path; 3 when nothing has been chosen yet (not set and no old file), so nothing is created before
# the user says where; 4 when it is off; 5 when the repository has no main worktree to read (bare, or a linked
# worktree of a --separate-git-dir repository) and no absolute path is set; 6 when mash-settings.sh path refuses the
# setting: it is the main worktree itself, the committed settings file names a place outside the repository (only
# settings.local or the environment variable may), a symbolic link leads from inside the repository to outside, or
# the home folder is a symbolic link, or an old ledger file (or a folder on its path) is a symbolic link. These refusals apply inside a git repository only; outside one, the path is
# printed as it is. An empty setting counts as not set.
# Outside a git repository, <repo-root> stands in for the main worktree and only REVIEW_ROUTING_ESCAPES is read
# (no settings files).
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
  if [[ -z "$choice" ]]; then status=3
  elif [[ "$choice" == off ]]; then exit 4
  elif ! is_absolute "$choice"; then choice="$main/$choice"
  fi
else
  # mash-settings.sh says why on stderr when it refuses (exit 5 or 6).
  choice=$(bash "$settings" path "$root" escapes) || status=$?
fi
case "$status" in
  0) ;;
  3) ;;
  *) exit "$status" ;;
esac
if (( status == 0 )); then
  if [[ -n "$main" ]]; then
    for other in docs/mash/review-escapes.md docs/review-escapes.md; do
      if [[ -f "$main/$other" && ! "$choice" -ef "$main/$other" ]]; then
        echo "escapes-path: $other holds escapes in the old format, which the report does not count: run escape-migrate.sh, then remove the file" >&2
        break
      fi
    done
  fi
  printf '%s\n' "$choice"
  exit 0
fi
if [[ -f "$main/docs/mash/review-escapes.md" && -f "$main/docs/review-escapes.md" ]]; then
  echo "escapes-path: both docs/mash/review-escapes.md and docs/review-escapes.md exist; using the first. escape-migrate.sh moves both into the escapes folder." >&2
fi
for candidate in docs/mash/review-escapes.md docs/review-escapes.md; do
  # A repository can commit a symbolic link: the report and the migration would read the file it names.
  if [[ -L "$main/$candidate" ]]; then
    echo "escapes-path: refused: $candidate is a symbolic link" >&2
    exit 6
  fi
  if [[ -f "$main/$candidate" ]]; then
    if (( main_status == 0 )); then
      # A repository can commit docs, or docs/mash, as a link: the file must be inside the main worktree.
      message=$(bash "$settings" check-escapes-path "$root" "$main/$candidate" 2>&1) || { echo "escapes-path: $candidate: $message" >&2; exit 6; }
    fi
    echo "escapes-path: old ledger format in use: $candidate; run escape-migrate.sh" >&2
    printf '%s\n' "$main/$candidate"
    exit 0
  fi
done
exit 3
