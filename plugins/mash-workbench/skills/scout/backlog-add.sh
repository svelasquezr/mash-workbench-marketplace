#!/usr/bin/env bash
# Append a tooling candidate to the project's tooling backlog (backlog-path.sh says which file; --create starts
# docs/mash/tooling-backlog.md, --file <path> another file, when the project has none yet). Skips duplicate titles; warns on stderr, and still adds, when
# an open entry's title is a near duplicate: at least 2 shared words of 3+ characters, covering 60% of the shorter
# title's. Words are runs of ASCII letters and digits, so a non-ASCII letter splits a word (a looser match, no more).
# Pros of warning rather than skipping: a loose match never drops a candidate. Cons: /forge has to merge the pair.
set -euo pipefail
usage="usage: backlog-add.sh [--create | --file <path>] <repo-root> <hook|script|skill|agent|mcp|unsure> <title> <why>"
explicit=""; positional=()
while (( $# > 0 )); do  # the flags may come anywhere before a --; after it everything is positional
  case "$1" in
    --) shift; positional+=("$@"); break ;;
    --create) explicit="docs/mash/tooling-backlog.md"; shift ;;
    --file) if (( $# < 2 )); then echo "$usage" >&2; exit 2; fi; explicit="$2"; shift 2 ;;
    -?*) echo "unknown option: $1 (a title or reason that starts with - goes after --)" >&2; echo "$usage" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- ${positional[@]+"${positional[@]}"}
root="$(cd "${1:?$usage}" && pwd -P)"
form="${2:?$usage}"; title="${3:?$usage}"; why="${4:?$usage}"
case "$form" in hook|script|skill|agent|mcp|unsure) ;; *) echo "unknown form: $form" >&2; echo "$usage" >&2; exit 2 ;; esac
# One entry is one line: a line break in the title or the reason (model-written text often has one) becomes a space.
title=$(printf '%s' "$title" | tr '\r\n' '  '); why=$(printf '%s' "$why" | tr '\r\n' '  ')
entry_date="${BACKLOG_DATE:-$(date -u +%F)}"
if ! [[ "$entry_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || ! python3 -c 'import datetime, sys; datetime.date.fromisoformat(sys.argv[1])' "$entry_date" 2>/dev/null; then
  echo "BACKLOG_DATE must be a date, YYYY-MM-DD: $entry_date" >&2; exit 2
fi
[[ "$title" =~ [^[:space:]] ]] || { echo "the title is empty" >&2; echo "$usage" >&2; exit 2; }
[[ "$title" != *" — "* ]] || { echo "the title must not contain ' — ': it separates the title from the reason" >&2; exit 2; }
if [[ "${MASH_WORKBENCH_BACKLOG:-}" == off ]]; then
  echo "the tooling backlog is off for this project (MASH_WORKBENCH_BACKLOG=off): nothing recorded"; exit 0
fi
if [[ -n "$explicit" ]]; then
  if [[ "$explicit" == /* ]]; then backlog_file="$explicit"; else backlog_file="$root/$explicit"; fi
  # A second backlog would split the open items /forge reads: refuse when the project already uses another one.
  status=0
  current=$(bash "$(dirname "${BASH_SOURCE[0]}")/backlog-path.sh" "$root" 2>/dev/null) || status=$?
  if (( status == 0 )) && [[ -f "$current" && ! "$current" -ef "$backlog_file" ]]; then
    echo "a backlog already exists at ${current#"$root"/}: use it (move it with git mv, or pass --file ${current#"$root"/}) instead of starting another" >&2
    exit 2
  fi
else
  status=0
  backlog_file=$(bash "$(dirname "${BASH_SOURCE[0]}")/backlog-path.sh" "$root") || status=$?
  case "$status" in
    0) ;;
    4) echo "the tooling backlog is off for this project (MASH_WORKBENCH_BACKLOG=off): nothing recorded"; exit 0 ;;
    3)
      {
        echo "no tooling backlog in this project yet: ask the user before creating one. Then re-run as"
        echo "  backlog-add.sh --create <repo-root> <form> <title> <why>        to start docs/mash/tooling-backlog.md, or"
        echo "  backlog-add.sh --file <path> <repo-root> <form> <title> <why>   to keep it in another file."
        echo "A ledger the team shares counts everyone's entries; one in .gitignore holds only yours: offer to add it to .gitignore, and recommend committing it."
        echo "To keep another file, or none, for later sessions, add to .claude/settings.local.json (only you) or"
        echo "  .claude/settings.json (everyone):  {\"env\": {\"MASH_WORKBENCH_BACKLOG\": \"<path, or off>\"}}"
      } >&2
      exit 3 ;;
    *) exit "$status" ;;
  esac
fi
mkdir -p "$(dirname "$backlog_file")"
if [[ ! -f "$backlog_file" ]]; then
  # shellcheck disable=SC2016 # backticks are literal markdown
  printf '# Tooling backlog\n\nCandidates noticed during sessions. Promote them with `/forge` (mash-workbench plugin).\n\n' > "$backlog_file"
fi
if grep -qiF "· $title —" "$backlog_file"; then echo "already in backlog: $title"; exit 0; fi
TITLE="$title" awk '
  function words(text, set,   parts, count, i, n) {
    n = split(tolower(text), parts, /[^a-z0-9]+/); count = 0
    for (i = 1; i <= n; i++) if (length(parts[i]) >= 3 && !(parts[i] in set)) { set[parts[i]] = 1; count++ }
    return count
  }
  BEGIN { new_count = words(ENVIRON["TITLE"], new_words) }
  /^- \[ \] / {
    line = $0; sub(/^- \[ \] [^·]*· [^·]*· /, "", line); sub(/ — .*/, "", line)
    split("", old_words); old_count = words(line, old_words); shared = 0
    for (word in old_words) if (word in new_words) shared++
    shorter = old_count < new_count ? old_count : new_count
    if (shared >= 2 && shared * 5 >= shorter * 3) print "near duplicate of: " line > "/dev/stderr"
  }' "$backlog_file"
if [[ -s "$backlog_file" && -n "$(tail -c1 "$backlog_file")" ]]; then printf '\n' >> "$backlog_file"; fi  # a file without a final newline
printf -- '- [ ] %s · %s · %s — %s\n' "$entry_date" "$form" "$title" "$why" >> "$backlog_file"
echo "added to backlog: $title"
