#!/usr/bin/env bash
# Print the review-escape ledger this project uses, as an absolute path.
#   REVIEW_ROUTING_ESCAPES set: that file (a relative path is from <repo-root>); "off": the project keeps none.
#   unset: docs/mash/review-escapes.md when it exists, else the older docs/review-escapes.md when it exists.
# Exit 0 with the path; 3 when no ledger has been chosen yet (unset and neither file exists), so nothing is
# created before the user says where; 4 when it is off. The variable is set in the env block of a Claude Code
# settings file: .claude/settings.local.json for yourself, .claude/settings.json for everyone in the project.
set -euo pipefail
usage="usage: escapes-path.sh <repo-root>"
[[ $# -eq 1 && -d "$1" ]] || { echo "$usage" >&2; exit 2; }
root="$(cd "$1" && pwd -P)"
choice="${REVIEW_ROUTING_ESCAPES:-}"
if [[ "$choice" == off ]]; then exit 4; fi
if [[ -n "$choice" ]]; then
  [[ "$choice" == /* ]] || choice="$root/$choice"
  printf '%s\n' "$choice"
  exit 0
fi
if [[ -f "$root/docs/mash/review-escapes.md" && -f "$root/docs/review-escapes.md" ]]; then
  echo "escapes-path: both docs/mash/review-escapes.md and docs/review-escapes.md exist; using the first. Merge the entries and remove the other so the report counts them all." >&2
fi
for candidate in docs/mash/review-escapes.md docs/review-escapes.md; do
  if [[ -f "$root/$candidate" ]]; then
    printf '%s\n' "$root/$candidate"
    exit 0
  fi
done
exit 3
