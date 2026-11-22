#!/usr/bin/env bash
# List open tooling backlog entries (in the file backlog-path.sh names) older than <days> (default 30), oldest first, as
# "<date> (<age> days) · <form> · <title>"; an open entry without a valid date follows as "undated · <entry>".
# No backlog (none chosen yet, or off), or no open entries: prints nothing, exit 0. BACKLOG_TODAY (YYYY-MM-DD) overrides
# today, for tests.
# Plain bash, no Python: the age is the difference of two day numbers (days since 0001-01-01), computed by hand, so it
# works the same on macOS, Linux and Git Bash (GNU `date -d` is not everywhere). It reads the backlog file and writes
# nothing.
# Exit codes: 0 listed (or nothing to list); 2 usage error, or BACKLOG_TODAY is not a date; 5 and 6 as backlog-path.sh.
set -euo pipefail
usage="usage: backlog-stale.sh <repo-root> [days]"
root="${1:?$usage}"; days="${2:-30}"
[[ "$days" =~ ^[0-9]{1,7}$ ]] || { echo "days must be a whole number: $days" >&2; echo "$usage" >&2; exit 2; }
days=$((10#$days))
status=0
backlog_file=$(bash "$(dirname "${BASH_SOURCE[0]}")/backlog-path.sh" "$root") || status=$?
case "$status" in 0) ;; 3 | 4) exit 0 ;; *) exit "$status" ;; esac  # 3: none chosen yet, 4: off
[[ -f "$backlog_file" ]] || exit 0

# day_number <YYYY-MM-DD>: sets number to the days since 0001-01-01; returns 1 when the text is not a real date.
number=0
day_number() {
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1
  local year=$((10#${BASH_REMATCH[1]})) month=$((10#${BASH_REMATCH[2]})) day=$((10#${BASH_REMATCH[3]})) last=31 leap=0 before
  if (( year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) )); then leap=1; fi
  case "$month" in
    4 | 6 | 9 | 11) last=30 ;;
    2) last=$((28 + leap)) ;;
  esac
  (( year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= last )) || return 1
  # The days before the first of each month, in a year that is not a leap year.
  local -a starts=(0 0 31 59 90 120 151 181 212 243 273 304 334)
  before=${starts[month]}
  if (( leap && month > 2 )); then before=$((before + 1)); fi
  number=$(( (year - 1) * 365 + (year - 1) / 4 - (year - 1) / 100 + (year - 1) / 400 + before + day ))
}

today_text="${BACKLOG_TODAY:-$(date -u +%F)}"
day_number "$today_text" || { echo "BACKLOG_TODAY must be YYYY-MM-DD: $today_text" >&2; exit 2; }
today=$number
dated=""; undated=""
separator=" — "
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  [[ "$line" == "- [ ] "* ]] || continue
  entry=${line#"- [ ] "}
  entry=${entry%%"$separator"*}
  if [[ "$entry" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" · "* ]] && day_number "${entry%%" · "*}"; then
    age=$((today - number))
    if (( age > days )); then dated+="${entry%%" · "*} ($age days) · ${entry#*" · "}"$'\n'; fi
  else
    undated+="undated · $entry"$'\n'
  fi
done < "$backlog_file"
# Oldest first; entries of one date keep the order of the file. The date is the first 10 characters of each line.
if [[ -n "$dated" ]]; then printf '%s' "$dated" | LC_ALL=C sort -s -k1,1; fi
printf '%s' "$undated"
