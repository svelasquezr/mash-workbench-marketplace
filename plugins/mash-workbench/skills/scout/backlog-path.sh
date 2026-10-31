#!/usr/bin/env bash
# Print the tooling backlog file this project uses, as an absolute path.
#   MASH_WORKBENCH_BACKLOG set: that file (a relative path is from <repo-root>); "off": the project keeps none.
#   unset: docs/mash/tooling-backlog.md when it exists, else the older docs/tooling-backlog.md when it exists.
# Exit 0 with the path; 3 when no backlog has been chosen yet (unset and neither file exists), so nothing is
# created before the user says where; 4 when it is off. The variable is set in the env block of a Claude Code
# settings file: .claude/settings.local.json for yourself, .claude/settings.json for everyone in the project.
set -euo pipefail
usage="usage: backlog-path.sh <repo-root>"
root="$(cd "${1:?$usage}" && pwd -P)"
choice="${MASH_WORKBENCH_BACKLOG:-}"
if [[ "$choice" == off ]]; then exit 4; fi
if [[ -n "$choice" ]]; then
  [[ "$choice" == /* ]] || choice="$root/$choice"
  printf '%s\n' "$choice"
  exit 0
fi
if [[ -f "$root/docs/mash/tooling-backlog.md" && -f "$root/docs/tooling-backlog.md" ]]; then
  echo "backlog-path: both docs/mash/tooling-backlog.md and docs/tooling-backlog.md exist; using the first. Merge the entries and remove the other." >&2
fi
for candidate in docs/mash/tooling-backlog.md docs/tooling-backlog.md; do
  if [[ -f "$root/$candidate" ]]; then
    printf '%s\n' "$root/$candidate"
    exit 0
  fi
done
exit 3
