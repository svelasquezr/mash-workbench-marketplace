#!/usr/bin/env bash
set -euo pipefail
# Count the review escapes in the project's escapes folder (escapes-path.sh) by area, most first, with the classes per
# area, and name each area that reached the threshold: it has earned a specialist reviewer (the add-reviewer skill).
#   area: N escapes (class 1, class 2)[ (K from one source: <link>)][ -> add a reviewer for area (add-reviewer skill)]
# Each escape file counts once, except that files of one area with the same source count once (a GitHub /pull/N and
# /issues/N with no fragment are the same source). Files without
# frontmatter, README.md and processed/ do not count.
# The threshold is --threshold N, else the escapes.threshold setting (scripts/mash-settings.sh), else 3.
# Concentration: when more than half of an area's escapes, and at least two, share one source without its #fragment
# (one pull request, shown as first spelled), the line says so: they may be one bug, not several.
# Declines: the setting declined.<area>=<YYYY-MM-DD>:<count> (the user said no to a reviewer at that count) replaces the
# "-> add a reviewer" suffix with "(declined on <date>)" until the area reaches <count> + 2.
# An old one-line-per-escape ledger file ("- YYYY-MM-DD · area · class · link") is still counted, one per distinct link
# and area, until it is migrated; stderr then says "old ledger format: run escape-migrate.sh".
# Exit 0 with a report (or "no escapes recorded"); 2 on a usage error or an unreadable ledger.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
settings="$here/../../scripts/mash-settings.sh"
usage="usage: escapes-report.sh <repo-root> [--threshold N]"
if [[ $# -lt 1 || ! -d "$1" ]]; then echo "$usage" >&2; exit 2; fi
root="$1"
shift
threshold=""
while (($# > 0)); do
  case "$1" in
    --threshold) if (($# < 2)); then echo "$usage" >&2; exit 2; fi; threshold="$2"; shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
if [[ -n "$threshold" ]]; then
  if ! [[ "$threshold" =~ ^[1-9][0-9]*$ ]]; then echo "$usage" >&2; exit 2; fi
else
  threshold=$(bash "$settings" get "$root" escapes.threshold 2>/dev/null || true)
  if [[ -z "$threshold" ]]; then
    threshold=3
  elif ! [[ "$threshold" =~ ^[1-9][0-9]*$ ]]; then
    echo "escapes-report: the escapes.threshold setting must be a whole number above 0, not \"$threshold\": using 3" >&2
    threshold=3
  fi
fi
status=0
ledger=$(bash "$here/escapes-path.sh" "$root") || status=$?
if ((status == 3 || status == 4)); then echo "no escapes recorded"; exit 0; fi  # none chosen yet, or off
if ((status != 0)); then exit "$status"; fi
if [[ -e "$ledger" && ! -r "$ledger" ]]; then echo "escapes-report: cannot read $ledger" >&2; exit 2; fi

# Rows as escape-fields.awk prints them: <name> <date> <area> <class> <source> <first line>, tab-separated.
rows=""
if [[ -f "$ledger" ]]; then
  echo "escapes-report: old ledger format: run escape-migrate.sh" >&2
  rows=$(tr -d '\r' < "$ledger" | awk -F ' · ' '
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] · / {
      date = substr($1, 3); area = $2; sub(/^(\.\/)+/, "", area); sub(/\/+$/, "", area)
      printf "\t%s\t%s\t%s\t%s\t\n", date, area, $3, $4
    }')
elif [[ -d "$ledger" ]]; then
  files=()
  for file in "$ledger"/*.md; do
    if [[ -f "$file" && "${file##*/}" != README.md ]]; then files+=("$file"); fi
  done
  if ((${#files[@]} > 0)); then rows=$(awk -f "$here/escape-fields.awk" "${files[@]}"); fi
fi
if [[ -z "$rows" ]]; then echo "no escapes recorded"; exit 0; fi

# One summary per area, in the order the areas first appear: <total> <area> <classes> <concentration note>.
summaries=$(printf '%s\n' "$rows" | awk -F '\t' '
  {
    area = $3; class = $4; source = $5
    if (source != "") {
      # A GitHub /pull/N and /issues/N are one number: an old ledger wrote every pull request as /issues/N.
      key = source
      if (key ~ /^https:\/\/github\.com\/[^\/]+\/[^\/]+\/pull\/[0-9]+$/) sub(/\/pull\//, "/issues/", key)
      if ((area SUBSEP key) in seen_source) next
      seen_source[area SUBSEP key] = 1
      shown = source; sub(/#.*/, "", shown)
      change = shown
      if (change ~ /^https:\/\/github\.com\/[^\/]+\/[^\/]+\/pull\/[0-9]+$/) sub(/\/pull\//, "/issues/", change)
      if (!((area SUBSEP change) in first_shown)) first_shown[area SUBSEP change] = shown
      per_change[area SUBSEP change]++
      if (per_change[area SUBSEP change] > best[area]) { best[area] = per_change[area SUBSEP change]; best_change[area] = first_shown[area SUBSEP change] }
    }
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
      note = ""
      if (best[area] >= 2 && best[area] * 2 > total[area]) note = best[area] " from one source: " best_change[area]
      printf "%d\t%s\t%s\t%s\n", total[area], area, text, note
    }
  }')

tab=$'\t'
while IFS="$tab" read -r total area classes note; do
  line="$area: $total $( ((total == 1)) && echo escape || echo escapes) ($classes)"
  if [[ -n "$note" ]]; then line="$line ($note)"; fi
  if ((total >= threshold)); then
    declined=$(bash "$settings" get "$root" "declined.$area" 2>/dev/null || true)
    if [[ "$declined" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}):([0-9]+)$ ]] && ((total < 10#${BASH_REMATCH[2]} + 2)); then
      line="$line (declined on ${BASH_REMATCH[1]})"
    else
      line="$line -> add a reviewer for $area (add-reviewer skill)"
    fi
  fi
  printf '%s\t%s\n' "$total" "$line"
done <<< "$summaries" | sort -t "$tab" -k1,1nr -s | cut -f2-
