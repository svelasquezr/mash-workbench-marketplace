#!/usr/bin/env bash
# Append a tooling candidate to the project's tooling backlog: one file, one line per entry. backlog-path.sh says which
# file, the same from every worktree (the setting is read from the main worktree). Skips duplicate titles; warns on
# stderr, and still adds, when an open entry's title is a near duplicate: at least 2 shared words of 3+ characters,
# covering 60% of the shorter title's. Words are runs of ASCII letters and digits, so a non-ASCII letter splits a word
# (a looser match, no more).
# Pros of warning rather than skipping: a loose match never drops a candidate. Cons: /forge has to merge the pair.
#
# Usage: backlog-add.sh <repo-root> <hook|script|skill|agent|mcp|unsure> <title> <why>
#
# No argument names the file to write: the place comes from the backlog setting (scripts/mash-settings.sh), which the
# user chose. With an allow rule this script runs with no prompt, so an argument must not be able to send the line to
# another file. (--create and --file are gone for that reason.)
# The script writes only to a new or empty file, or to a file whose first line is the title "# Tooling backlog"
# (exit 6 otherwise): a setting cannot make it add a line to another kind of file.
# The file starts with a title and a "repo:" line that names the owning repository (mash-settings.sh repo-key). A file
# that has a title and no "repo:" line gets the line on the next write. A file outside the main worktree whose "repo:"
# line names another repository is refused.
# A backlog from before the setting existed (docs/mash/tooling-backlog.md or docs/tooling-backlog.md, no setting) still
# gets the entry; stderr then says how to give it a setting, or how to move it.
#
# Exit codes: 0 added, already in the backlog, or the backlog is off (nothing recorded); 2 usage error or a field that
# fails its check; 3 no backlog chosen yet (the message says what to ask the user); 5 no main worktree and no absolute
# path set; 6 refused: the file fails mash-settings.sh path or check-backlog-path (a linked worktree, a temporary
# folder, the git directory, a file another repository owns, a place outside the repository that the committed
# settings file chose, a symbolic link), or this copy of the plugin is an old version in Claude Code's plugin cache
# (scripts/plugin-current.sh).
# Plain bash 3.2 (macOS) and Git Bash, no python3: on Windows python3 is often the Microsoft Store stub.
set -euo pipefail
# Exit 6 also when <repo-root> is in a folder shaped like a git directory (mash-settings.sh refuses it before git runs).
# Exit 6 also when <repo-root> is not in the repository of the current folder (outside git: when the current folder
# is not inside <repo-root>): an allow rule approves any arguments, so a line goes only to the session's project.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bash "$here/../../scripts/plugin-current.sh" < /dev/null || exit $?
settings=$(cd "$here/../../scripts" && pwd -P)/mash-settings.sh
usage="usage: backlog-add.sh <repo-root> <hook|script|skill|agent|mcp|unsure> <title> <why>"
quote() { printf '%q' "$1"; }  # a path in a printed command, safe to paste
positional=()
while (( $# > 0 )); do  # after a -- everything is positional
  case "$1" in
    --) shift; positional+=("$@"); break ;;
    --create | --file)
      echo "backlog-add: $1 is gone: choose the backlog file with bash $settings set <repo-root> backlog <path> --team (or --local), then run this command without $1" >&2
      echo "$usage" >&2; exit 2 ;;
    -?*) echo "unknown option: $1 (a title or reason that starts with - goes after --)" >&2; echo "$usage" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- ${positional[@]+"${positional[@]}"}
[[ $# -eq 4 ]] || { echo "$usage" >&2; exit 2; }
[[ -d "$1" ]] || { echo "backlog-add: no such repository root: $1" >&2; echo "$usage" >&2; exit 2; }
root="$(cd "$1" && pwd -P)"
form="$2"; title="$3"; why="$4"
case "$form" in hook|script|skill|agent|mcp|unsure) ;; *) echo "unknown form: $form" >&2; echo "$usage" >&2; exit 2 ;; esac
# One entry is one line: a line break in the title or the reason (model-written text often has one) becomes a space.
title=$(printf '%s' "$title" | tr '\r\n' '  '); why=$(printf '%s' "$why" | tr '\r\n' '  ')
valid_date() {
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1
  local year=$((10#${BASH_REMATCH[1]})) month=$((10#${BASH_REMATCH[2]})) day=$((10#${BASH_REMATCH[3]})) last=31
  case "$month" in
    4|6|9|11) last=30 ;;
    2) if (( year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) )); then last=29; else last=28; fi ;;
  esac
  (( year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= last ))
}
entry_date="${BACKLOG_DATE:-$(date -u +%F)}"
valid_date "$entry_date" || { echo "BACKLOG_DATE must be a date, YYYY-MM-DD: $entry_date" >&2; exit 2; }
[[ "$title" =~ [^[:space:]] ]] || { echo "the title is empty" >&2; echo "$usage" >&2; exit 2; }
[[ "$title" != *" — "* ]] || { echo "the title must not contain ' — ': it separates the title from the reason" >&2; exit 2; }

# clean: no control characters in what is printed from files or folder names (a commit can hold either).
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177' | LC_ALL=C awk '{ gsub(/\302[\200-\237]/, ""); print }'; }
# A <repo-root> whose name holds a control character is refused before any message names it.
if [[ "$root" == *$'\t'* || "$(printf '%s' "$root" | clean)" != "$root" ]]; then
  echo "backlog-add: refused: the folder name of <repo-root> holds a control character" >&2
  exit 6
fi
# in_git: the path checks, the settings files and the owner line need a git repository.
in_git=1
main_status=0
main=$(bash "$settings" main-worktree "$root" 2>/dev/null) || main_status=$?
case "$main_status" in
  0) ;;
  2) in_git=""; main="$root" ;;
  *) main="" ;;  # 5, or 6 (backlog-path.sh below refuses with the message)
esac
# A line goes only to the project the session works in: an allow rule approves any <repo-root>, so one that names
# another repository (or, outside git, a folder that does not hold the current folder) is refused (exit 6).
if [[ -n "$in_git" ]]; then
  bash "$settings" same-repository "$root" || exit $?
else
  # Outside git means the session is outside git too: a <repo-root> above the session's repository is refused.
  here_status=0
  bash "$settings" main-worktree "$(pwd -P)" >/dev/null 2>&1 || here_status=$?
  if ((here_status != 2)); then
    echo "backlog-add: refused: $root is not in a git repository, but the current folder ($(pwd -P)) is in or under one (or in a folder git would take as one): a line goes only to the repository the session works in." | clean >&2
    exit 6
  fi
  case "$(pwd -P)/" in
    "$root"/*) ;;
    *) echo "backlog-add: refused: the current folder ($(pwd -P)) is not inside $root: a line goes only to the project the session works in. Run the command from inside it." | clean >&2; exit 6 ;;
  esac
fi
status=0
backlog_file=$(bash "$here/backlog-path.sh" "$root") || status=$?
case "$status" in
  0) ;;
  4) echo "the tooling backlog is off for this project: nothing recorded"; exit 0 ;;
  3)
    {
      echo "no tooling backlog chosen yet: ask the user where to keep it, then run"
      if [[ -n "$in_git" ]]; then
        echo "  bash $(quote "$settings") set $(quote "$root") backlog <path, or off> --team   (a committed backlog: the team shares it)"
        echo "  bash $(quote "$settings") set $(quote "$root") backlog <path, or off> --local  (only this clone, or a file outside the repo)"
        echo "The default is docs/mash/tooling-backlog.md; check a path first with: bash $(quote "$settings") check-backlog-path $(quote "$root") <path>"
      else
        echo "  (this folder is not in a git repository, so there is no settings file) set MASH_WORKBENCH_BACKLOG=<path, or off> in your environment"
      fi
      echo "Then run this command again. \"Setting up the backlog\" in the scout skill's reference.md has the details and the permission rule."
    } >&2
    exit 3 ;;
  *) exit "$status" ;;
esac
if [[ -n "$in_git" ]]; then
  status=0
  message=$(bash "$settings" check-backlog-path "$root" "$backlog_file" 2>&1) || status=$?
  if (( status != 0 )); then echo "backlog-add: $backlog_file: $message" >&2; exit "$status"; fi
fi
# A repository can commit a symbolic link: the line would go where it points.
if [[ -L "$backlog_file" ]]; then echo "backlog-add: $backlog_file is a symbolic link: nothing recorded" >&2; exit 6; fi
[[ ! -d "$backlog_file" ]] || { echo "backlog-add: the backlog path is a folder: $backlog_file" >&2; exit 6; }
key=""
if [[ -n "$in_git" ]]; then key=$(bash "$settings" repo-key "$root" 2>/dev/null || true); fi
# Outside git, a path that climbs out with ".." is refused before any folder is made (inside git, the path checks
# above have already placed it).
if [[ -z "$in_git" ]]; then
  case "/$backlog_file/" in */../*) echo "backlog-add: refused: the backlog path climbs out of its folder with ..: $backlog_file" >&2; exit 6 ;; esac
fi
mkdir -p "$(dirname "$backlog_file")"
if [[ -n "$in_git" ]]; then
  # Once more, now that the folder exists: every name on the path can be resolved.
  status=0
  message=$(bash "$settings" check-backlog-path "$root" "$backlog_file" 2>&1) || status=$?
  if (( status != 0 )); then echo "backlog-add: $backlog_file: $message" >&2; exit "$status"; fi
else
  # Outside a git repository there are no settings and no path checks, but a link must not move the write out of
  # <repo-root>: the folder of a file that was named relative to it must resolve inside it.
  folder_real=$(cd "$(dirname "$backlog_file")" && pwd -P)
  case "$backlog_file" in
    "$root"/*) case "$folder_real/" in "$root"/*) ;; *) echo "backlog-add: a symbolic link on $backlog_file leads outside $root: nothing recorded" >&2; exit 6 ;; esac ;;
  esac
fi
# The setting can name any file, and a committed setting names one inside the repository with no question. So the
# script writes only to a new file, an empty .md file, or a file that starts with the backlog title: never a line into
# a .env or a source file (an empty __init__.py included).
backlog_title="# Tooling backlog"
if [[ -e "$backlog_file" && ! -r "$backlog_file" ]]; then
  echo "backlog-add: cannot read $backlog_file: nothing recorded. Give the user read access to it, or name another file in the backlog setting." >&2
  exit 6
fi
if [[ -e "$backlog_file" && ! -s "$backlog_file" ]]; then
  case "$(printf '%s' "$backlog_file" | tr '[:upper:]' '[:lower:]')" in
    *.md) ;;
    *) echo "backlog-add: $backlog_file is an empty file whose name does not end in .md: it is not a tooling backlog. Nothing recorded. Name a .md file in the backlog setting." >&2
      exit 6 ;;
  esac
fi
if [[ -s "$backlog_file" ]]; then
  IFS= read -r first_line < "$backlog_file" || true
  if [[ "${first_line%$'\r'}" != "$backlog_title" ]]; then
    echo "backlog-add: $backlog_file is not a tooling backlog: its first line is not \"$backlog_title\". Nothing recorded. Name another file in the backlog setting, or add that title line to the file." >&2
    exit 6
  fi
fi
if [[ ! -s "$backlog_file" ]]; then
  {
    printf '# Tooling backlog\n'
    if [[ -n "$key" ]]; then printf 'repo: %s\n' "$key"; fi
    # shellcheck disable=SC2016 # backticks are literal markdown
    printf '\nCandidates noticed during sessions. Promote them with `/forge` (mash-workbench plugin).\n\n'
  } > "$backlog_file"
elif [[ -n "$key" ]] && ! grep -q '^repo:' "$backlog_file" && [[ "$(head -n 1 "$backlog_file")" == "# "* ]]; then
  # The owner line goes under the title. Through a copy in the same folder, so the file keeps its mode and the mv
  # replaces it in one step.
  temporary="$backlog_file.$$.tmp"
  rm -f "$temporary"
  cp -p "$backlog_file" "$temporary"
  KEY="$key" awk 'NR == 1 { eol = ($0 ~ /\r$/) ? "\r" : ""; print; print "repo: " ENVIRON["KEY"] eol; next } { print }' "$backlog_file" > "$temporary"
  mv "$temporary" "$backlog_file"
fi
if grep -qiF -- "· $title —" "$backlog_file"; then echo "already in backlog: $title"; exit 0; fi
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
    if (shared >= 2 && shared * 5 >= shorter * 3) print "near duplicate of: " line
  }' "$backlog_file" | clean >&2  # the line comes from the backlog file (a commit can hold it)
if [[ -s "$backlog_file" && -n "$(tail -c1 "$backlog_file")" ]]; then printf '\n' >> "$backlog_file"; fi  # a file without a final newline
printf -- '- [ ] %s · %s · %s — %s\n' "$entry_date" "$form" "$title" "$why" >> "$backlog_file"
echo "added to backlog: $title"
# A backlog from before the setting existed: say how to give it one. Only in a git repository (the settings files).
if [[ -n "$in_git" && -n "$main" ]] && ! bash "$settings" get "$root" backlog >/dev/null 2>&1; then
  old=${backlog_file#"$main"/}
  {
    echo "backlog-add: this backlog has no setting yet (it was found at its old place, $old). Ask the user once: keep it there, or move it. Then run"
    echo "  bash $(quote "$settings") set $(quote "$root") backlog $(quote "$old") --team        (keep it there)"
    echo "or, to move it:  git -C $(quote "$main") mv $(quote "$old") <new path>  and  bash $(quote "$settings") set $(quote "$root") backlog <new path> --team"
    echo "\"Old backlog file\" in the scout skill's reference.md says why."
  } >&2
fi
