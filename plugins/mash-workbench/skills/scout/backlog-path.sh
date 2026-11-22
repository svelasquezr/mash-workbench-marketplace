#!/usr/bin/env bash
# Print the tooling backlog file this project uses, as an absolute path. The answer is the same from every worktree:
# the setting and the old files are read from the main worktree (scripts/mash-settings.sh), never from <repo-root>.
#   The backlog setting (mash-settings.sh path <repo-root> backlog: MASH_WORKBENCH_BACKLOG, then
#   <main>/.claude/mash-workbench/settings.local, then settings): that file, a relative one from the main worktree;
#   "off": the project keeps none.
#   Not set: docs/mash/tooling-backlog.md in the main worktree when it exists, else the older docs/tooling-backlog.md
#   (a backlog from before the setting existed keeps working; backlog-add.sh says how to give it a setting).
# Exit 0 with the path; 3 when no backlog has been chosen yet (not set and neither file exists), so nothing is created
# before the user says where; 4 when it is off; 5 when the repository has no main worktree to read (a linked worktree of a bare
# repository or of a --separate-git-dir repository) and no absolute path is set; 6 when the path is refused: the main
# worktree itself, a place outside the repository that the committed settings file names (only settings.local or the
# environment variable may choose one), a symbolic link that leads from inside the repository to outside, an old file
# that is a symbolic link, or a home folder that is a symbolic link.
# Outside a git repository, <repo-root> stands in for the main worktree, only MASH_WORKBENCH_BACKLOG and the old files
# are read (no settings files), and the refusals above do not apply.
set -euo pipefail
# Exit 6 also when <repo-root> is in a folder shaped like a git directory (mash-settings.sh refuses it before git runs).
usage="usage: backlog-path.sh <repo-root>"
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
  *) bash "$settings" main-worktree "$root" >/dev/null || true  # once more, for its message on stderr
    exit "$main_status" ;;
esac
status=0
if (( main_status == 2 )); then
  choice="${MASH_WORKBENCH_BACKLOG:-}"
  if [[ -z "${choice//[[:space:]]/}" ]]; then status=3
  elif [[ "$choice" == off ]]; then exit 4
  elif ! is_absolute "$choice"; then choice="$main/$choice"
  fi
else
  # mash-settings.sh says why on stderr when it refuses (exit 5 or 6).
  choice=$(bash "$settings" path "$root" backlog) || status=$?
fi
case "$status" in
  0) ;;
  3) ;;
  *) exit "$status" ;;
esac
if (( status == 0 )); then
  if [[ -n "$main" ]]; then
    for other in docs/mash/tooling-backlog.md docs/tooling-backlog.md; do
      if [[ ! -f "$choice" && -f "$main/$other" ]]; then
        echo "backlog-path: the backlog setting names a new file, but $other already holds a backlog; /forge will not read it. Move it there with git mv, or point the setting at it." >&2
        break
      fi
    done
  fi
  printf '%s\n' "$choice"
  exit 0
fi
[[ -n "$main" ]] || exit 3
if [[ -f "$main/docs/mash/tooling-backlog.md" && -f "$main/docs/tooling-backlog.md" ]]; then
  echo "backlog-path: both docs/mash/tooling-backlog.md and docs/tooling-backlog.md exist; using the first. Merge the entries and remove the other." >&2
fi
for candidate in docs/mash/tooling-backlog.md docs/tooling-backlog.md; do
  # -L first: a dangling symbolic link is not a file, and a write would still follow it.
  if [[ -L "$main/$candidate" ]]; then
    echo "backlog-path: refused: $candidate is a symbolic link" >&2
    exit 6
  fi
  if [[ -f "$main/$candidate" ]]; then
    if (( main_status == 0 )); then
      # A repository can commit a symbolic link as docs/ or docs/mash: the file must be inside the main worktree.
      message=$(bash "$settings" check-backlog-path "$root" "$main/$candidate" 2>&1) || { echo "backlog-path: $candidate: $message" >&2; exit 6; }
    fi
    printf '%s\n' "$main/$candidate"
    exit 0
  fi
done
exit 3
