#!/usr/bin/env bash
# List open tooling backlog entries (in the file backlog-path.sh names) older than <days> (default 30), oldest first, as
# "<date> (<age> days) · <form> · <title>"; an open entry without a valid date follows as "undated · <entry>".
# No backlog (none chosen yet, or off), or no open entries: prints nothing, exit 0. BACKLOG_TODAY (YYYY-MM-DD) overrides today, for tests.
# Date math runs in Python (standard library) rather than GNU `date -d`, so it also works on macOS.
set -euo pipefail
usage="usage: backlog-stale.sh <repo-root> [days]"
root="${1:?$usage}"; days="${2:-30}"
[[ "$days" =~ ^[0-9]+$ ]] || { echo "days must be a whole number: $days" >&2; echo "$usage" >&2; exit 2; }
status=0
backlog_file=$(bash "$(dirname "${BASH_SOURCE[0]}")/backlog-path.sh" "$root") || status=$?
case "$status" in 0) ;; 3 | 4) exit 0 ;; *) exit "$status" ;; esac  # 3: none chosen yet, 4: off
[[ -f "$backlog_file" ]] || exit 0
python3 - "$backlog_file" "$days" "${BACKLOG_TODAY:-}" <<'PY'
import datetime, re, sys
path, days, today_text = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    today = datetime.date.fromisoformat(today_text) if today_text else datetime.datetime.now(datetime.timezone.utc).date()
except ValueError:
    print(f"BACKLOG_TODAY must be YYYY-MM-DD: {today_text}", file=sys.stderr)
    sys.exit(2)
dated, undated = [], []
for line in open(path, encoding="utf-8", errors="replace"):
    if not line.startswith("- [ ] "):
        continue
    entry = line[len("- [ ] "):].rstrip("\n").split(" — ", 1)[0]
    match = re.match(r"(\d{4}-\d{2}-\d{2}) · (.*)", entry)
    try:
        entry_date = datetime.date.fromisoformat(match.group(1)) if match else None
    except ValueError:
        entry_date = None
    if entry_date is None:
        undated.append(f"undated · {entry}")
    elif (today - entry_date).days > days:
        dated.append((entry_date, f"{entry_date} ({(today - entry_date).days} days) · {match.group(2)}"))
for _, text in sorted(dated, key=lambda item: item[0]):
    print(text)
for text in undated:
    print(text)
PY
