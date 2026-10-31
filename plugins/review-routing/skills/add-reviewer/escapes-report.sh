#!/usr/bin/env bash
# Count the review escapes in the project's ledger (escapes-path.sh) by area, most first, and name each
# area that reached the threshold (default 2): it has earned a specialist reviewer (the add-reviewer
# skill). Each distinct link counts once per area, so a duplicated line does not inflate a count. Only
# entry lines count ("- YYYY-MM-DD · area · class · link"); prose in the file is ignored.
# Exit 0 with a report (or "no escapes recorded"); 2 on a usage error or an unreadable ledger.
set -euo pipefail
usage="usage: escapes-report.sh <repo-root> [--threshold N]"
if [[ $# -lt 1 || ! -d "$1" ]]; then echo "$usage" >&2; exit 2; fi
root="$1"
shift
threshold=""
while (( $# > 0 )); do
  case "$1" in
    --threshold) if (( $# < 2 )); then echo "$usage" >&2; exit 2; fi; threshold="$2"; shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
threshold="${threshold:-2}"
if ! [[ "$threshold" =~ ^[1-9][0-9]*$ ]]; then echo "$usage" >&2; exit 2; fi
status=0
ledger=$(bash "$(dirname "${BASH_SOURCE[0]}")/escapes-path.sh" "$root") || status=$?
if (( status == 3 || status == 4 )); then echo "no escapes recorded"; exit 0; fi  # none chosen yet, or off
if (( status != 0 )); then exit "$status"; fi
if [[ -e "$ledger" && ! -r "$ledger" ]]; then echo "escapes-report: cannot read $ledger" >&2; exit 2; fi
entry_pattern='^- [0-9]{4}-[0-9]{2}-[0-9]{2} · '
if [[ ! -f "$ledger" ]] || ! grep -qE "$entry_pattern" "$ledger"; then
  echo "no escapes recorded"
  exit 0
fi
grep -E "$entry_pattern" "$ledger" | tr -d '\r' | awk -F ' · ' -v threshold="$threshold" '
  {
    area = $2; sub(/^(\.\/)+/, "", area); sub(/\/+$/, "", area); class = $3
    if ((area SUBSEP $4) in seen_link) next
    seen_link[area SUBSEP $4] = 1
    if (!(area in total)) order[++count] = area
    total[area]++
    key = area SUBSEP class
    if (!(key in per_class)) classes[area] = classes[area] (classes[area] == "" ? "" : SUBSEP) class
    per_class[key]++
  }
  END {
    for (index_ = 1; index_ <= count; index_++) {
      area = order[index_]
      split(classes[area], names, SUBSEP)
      text = ""
      for (name_index = 1; name_index in names; name_index++) {
        text = text (name_index > 1 ? ", " : "") names[name_index] " " per_class[area SUBSEP names[name_index]]
      }
      line = sprintf("%s: %d %s (%s)", area, total[area], total[area] == 1 ? "escape" : "escapes", text)
      if (total[area] >= threshold) line = line " -> add a reviewer for " area " (add-reviewer skill)"
      printf "%d\t%s\n", total[area], line
    }
  }' | sort -t "$(printf '\t')" -k1,1nr -s | cut -f2-
