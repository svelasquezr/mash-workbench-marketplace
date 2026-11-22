#!/usr/bin/env bash
set -euo pipefail
# Move an old one-line-per-escape ledger into the escapes folder, one file per entry, so every worktree finds the
# escapes in one place. Ask the user before running it (the add-reviewer and review-changes skills say why).
#
# Usage: escape-migrate.sh <repo-root>
#
# The old ledgers: the file the escapes setting names (REVIEW_ROUTING_ESCAPES, settings.local, settings) when it names a
# file, and docs/mash/review-escapes.md and docs/review-escapes.md in the main worktree. Each entry line
# "- DATE · AREA · CLASS · LINK" becomes <date>-migrated-<n>.md with "source: LINK" and the body "Migrated; see source."
# through escape-add.sh --batch, which checks every entry first and skips a source the folder already holds, so a
# second run adds nothing. A line that starts like an entry but has not four fields is skipped and named.
# The target folder: the escapes setting when it names a folder; otherwise <main>/.claude/mash-workbench/escapes.
# The script never deletes the old file and never changes a setting: it prints the commands for the user (git rm or rm,
# and mash-settings.sh set when the setting must name the new folder).
# Exit codes: 0 migrated, or no old ledger found; 2 usage error, not in a git repository, or an entry that fails
# escape-add.sh's checks (nothing written); 4 the escapes ledger is off; 5 no main worktree (bare repository); 6 the
# target folder is refused by mash-settings.sh check-escapes-path.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
settings=$(cd "$here/../../scripts" && pwd -P)/mash-settings.sh
usage() { echo "usage: escape-migrate.sh <repo-root>" >&2; exit 2; }
[[ $# -eq 1 && -d "$1" ]] || usage
root=$(cd "$1" && pwd -P)
status=0
main=$(bash "$settings" main-worktree "$root" 2>/dev/null) || status=$?
case "$status" in
  0) ;;
  2) echo "escape-migrate: not in a git repository: $root" >&2; exit 2 ;;
  *) echo "escape-migrate: no main worktree (bare repository): migrate from a clone with a work folder" >&2; exit "$status" ;;
esac
quote() { printf '%q' "$1"; }  # a path in a printed command, safe to paste
display() { if [[ "$1" == "$main"/* ]]; then printf '%s' "${1#"$main"/}"; else printf '%s' "$1"; fi; }

status=0
current=$(bash "$here/escapes-path.sh" "$root" 2>/dev/null) || status=$?
case "$status" in
  0 | 3) ;;
  4) echo "the escapes ledger is off for this project: nothing migrated"; exit 4 ;;
  *) exit "$status" ;;
esac
old_files=()
target=""
if ((status == 0)); then
  if [[ -f "$current" ]]; then old_files+=("$current"); else target=$current; fi
fi
for candidate in docs/mash/review-escapes.md docs/review-escapes.md; do
  if [[ -f "$main/$candidate" ]] && { ((${#old_files[@]} == 0)) || ! [[ "${old_files[0]}" -ef "$main/$candidate" ]]; }; then
    old_files+=("$main/$candidate")
  fi
done
if ((${#old_files[@]} == 0)); then echo "no old ledger found: nothing to migrate"; exit 0; fi
setting_needed=""
if [[ -z "$target" ]]; then target="$main/.claude/mash-workbench/escapes"; setting_needed=1; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Each block's <old file>:<line> goes to $work/lines, one per block in order, so an error names the old line.
: > "$work/lines"
for old in "${old_files[@]}"; do
  [[ -r "$old" ]] || { echo "escape-migrate: cannot read $old" >&2; exit 2; }
  DISPLAY_NAME="$(display "$old")" LINES_FILE="$work/lines" awk -F ' · ' -v entries="$(wc -l < "$work/lines" | tr -d ' ')" '
    { sub(/\r$/, "") }
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]( |$)/ {
      if (NF != 4) { printf "skipped line %d of %s: %s\n", FNR, ENVIRON["DISPLAY_NAME"], $0 > "/dev/stderr"; next }
      for (field = 1; field <= 4; field++) gsub(/^[ \t]+|[ \t]+$/, "", $field)
      printf "---\ndate: %s\narea: %s\nclass: %s\nslug: migrated-%d\nsource: %s\n---\nMigrated; see source.\n---8<---\n", substr($1, 3), $2, $3, ++entries, $4
      print ENVIRON["DISPLAY_NAME"] ":" FNR >> ENVIRON["LINES_FILE"]
    }' "$old" >> "$work/batch" 2>> "$work/skipped"
done
if [[ -s "$work/skipped" ]]; then cat "$work/skipped"; fi
if [[ -s "$work/batch" ]]; then
  status=0
  # The variable points escape-add.sh at the target folder for this run only. Its escapes-path.sh warnings about the old
  # files are left out: the steps below say what to do with them.
  REVIEW_ROUTING_ESCAPES="$target" bash "$here/escape-add.sh" --batch - "$root" < "$work/batch" 2> "$work/errors" || status=$?
  # escape-add.sh names a bad block by its number: name the old file and line instead.
  awk 'NR == FNR { line[FNR] = $0; next }
    /^escapes-path: / { next }
    /^escape-add: block [0-9]+: / {
      number = $3; sub(/:$/, "", number); text = $0; sub(/^escape-add: block [0-9]+: /, "", text)
      print "escape-migrate: " line[number] ": " text; next
    }
    { print }' "$work/lines" "$work/errors" >&2 || true
  if ((status != 0)); then exit "$status"; fi
else
  echo "no entry lines found: nothing recorded"
fi

echo "The escapes are now in $(display "$target"). The old file stays until you remove it; ask the user, then run:"
for old in "${old_files[@]}"; do
  if [[ "$old" == "$main"/* ]] && git -C "$main" ls-files --error-unmatch -- "$(display "$old")" >/dev/null 2>&1; then
    echo "  git -C $(quote "$main") rm $(quote "$(display "$old")")"
  else
    echo "  rm $(quote "$old")"
  fi
done
if [[ -n "$setting_needed" ]]; then
  scope=--local
  if [[ "$(bash "$settings" check-escapes-path "$root" "$target" 2>/dev/null || true)" == "inside the repo: commit"* ]]; then scope=--team; fi
  echo "  bash $(quote "$settings") set $(quote "$root") escapes $(quote "$(display "$target")") $scope"
  if [[ -n "${REVIEW_ROUTING_ESCAPES:-}" ]]; then
    echo "  and remove REVIEW_ROUTING_ESCAPES from .claude/settings*.json (the env block): it wins over the settings files"
  fi
fi
