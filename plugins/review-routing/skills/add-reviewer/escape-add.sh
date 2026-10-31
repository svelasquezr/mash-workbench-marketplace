#!/usr/bin/env bash
# Record a review escape: a bug in code a review passed, found later by anyone (a person, CI or a later
# reviewer). One line per bug, keyed by its issue link, in the project's ledger (escapes-path.sh says which file;
# --create starts docs/mash/review-escapes.md, --file <path> another file, when the project has none yet); a link the
# ledger already holds is not added again (exit 0, "already recorded"). A GitHub issue or PR URL, owner/repo#N
# and #N (owner/repo from the origin remote) are all written as https://github.com/<owner>/<repo>/issues/N,
# so one bug has one spelling; owner and repo are lowercased, and www., a #fragment and a ?query are dropped from GitHub URLs; any other link only loses a trailing slash. The lines are the evidence
# escapes-report.sh uses to say when an area has earned a specialist reviewer; when the area is at or over
# the threshold (default 2) after this entry, that area's report line is printed too.
# The area is the directory a [[routes]] pattern would claim (src/payments), never a file.
set -euo pipefail
usage="usage: escape-add.sh [--create | --file <path>] <repo-root> <area-directory> <class> <issue link>"
refuse() { echo "escape-add: $*" >&2; echo "$usage" >&2; exit 2; }
explicit=""; positional=()
while (( $# > 0 )); do
  case "$1" in
    --create) explicit="docs/mash/review-escapes.md"; shift ;;
    --file) if (( $# < 2 )); then refuse "--file needs a path"; fi; explicit="$2"; shift 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- ${positional[@]+"${positional[@]}"}
if [[ $# -ne 4 ]]; then refuse "four arguments needed"; fi
[[ -d "$1" ]] || refuse "no such repository root: $1"
root="$(cd "$1" && pwd -P)"
area="$2"
while [[ "$area" == ./* ]]; do area="${area#./}"; done
while [[ "$area" == ?*/ ]]; do area="${area%/}"; done
class="$3"
link="$4"
area=$(printf '%s' "$area" | tr -s '/')  # src//payments is src/payments
[[ -n "$area" && -n "$class" && -n "$link" ]] || refuse "area, class and link must not be empty"
[[ "$area" != "." && "$area" != /* && "/$area/" != */../* ]] \
  || refuse "the area is a directory inside the repository, such as src/payments"
[[ "$area$class$link" != *"·"* ]] || refuse "the · character separates fields; leave it out"
[[ "$area$class$link" != *$'\n'* && "$area$class$link" != *$'\r'* ]] || refuse "fields must be on one line"
[[ "$area" != *[[:space:]]* ]] || refuse "the area must not contain whitespace: $area"
[[ "$class" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || refuse "the class is lowercase words joined by hyphens, such as wrong-result"
entry_date="${ESCAPE_DATE:-$(date -u +%F)}"
if ! [[ "$entry_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || ! python3 -c 'import datetime, sys; datetime.date.fromisoformat(sys.argv[1])' "$entry_date" 2>/dev/null; then
  refuse "ESCAPE_DATE must be a date, YYYY-MM-DD: $entry_date"
fi
[[ ! -f "$root/$area" ]] || refuse "the area is a directory, not a file: use $(dirname "$area")"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }  # tr, not bash 4 case expansion: macOS ships bash 3.2
while [[ "$link" == ?*/ ]]; do link="${link%/}"; done
if [[ "$(lower "$link")" =~ ^(https?://(www\.)?github\.com/) ]]; then
  link="https://github.com/${link:${#BASH_REMATCH[1]}}"
fi
if [[ "$link" =~ ^https?://(www\.)?github\.com/ ]]; then
  link="${link%%#*}"
  link="${link%%\?*}"
  while [[ "$link" == ?*/ ]]; do link="${link%/}"; done
  # A pull request's files, commits or checks page is the pull request.
  if [[ "$link" =~ ^(https://github\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+)/(files|commits|checks)(/.*)?$ ]]; then
    link="${BASH_REMATCH[1]}"
  fi
fi
if [[ "$link" =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)$ ]]; then
  link="$(printf 'https://github.com/%s/%s/issues/%s' "$(lower "${BASH_REMATCH[2]}")" "$(lower "${BASH_REMATCH[3]}")" "${BASH_REMATCH[5]}")"
elif [[ "$link" =~ ^([^/#[:space:]]+/[^/#[:space:]]+)#([0-9]+)$ ]]; then
  link="https://github.com/$(lower "${BASH_REMATCH[1]}")/issues/${BASH_REMATCH[2]}"
elif [[ "$link" =~ ^#([0-9]+)$ ]]; then
  number="${BASH_REMATCH[1]}"
  origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  origin="${origin%/}"
  if [[ "$origin" =~ ^(https?://([^/@]+@)?|ssh://git@|git@)github\.com[:/]+([^/]+/[^/]+)$ ]]; then
    slug="${BASH_REMATCH[3]%.git}"
    link="https://github.com/$(lower "$slug")/issues/$number"
  else
    refuse "cannot resolve $link: the origin remote of $root is not a GitHub repository; give the full issue URL"
  fi
fi
[[ "$link" =~ ^https?://[^[:space:]]+$ ]] || refuse "the link must be a GitHub issue or pull request, owner/repo#N, #N, or an http(s) URL: $link"
if [[ "${REVIEW_ROUTING_ESCAPES:-}" == off ]]; then
  echo "the escape ledger is off for this project (REVIEW_ROUTING_ESCAPES=off): nothing recorded"; exit 0
fi
if [[ -n "$explicit" ]]; then
  if [[ "$explicit" == /* ]]; then ledger="$explicit"; else ledger="$root/$explicit"; fi
else
  status=0
  ledger=$(bash "$(dirname "${BASH_SOURCE[0]}")/escapes-path.sh" "$root") || status=$?
  case "$status" in
    0) ;;
    4) echo "the escape ledger is off for this project (REVIEW_ROUTING_ESCAPES=off): nothing recorded"; exit 0 ;;
    3)
      {
        echo "no escape ledger in this project yet: ask the user before creating one. Then re-run as"
        echo "  escape-add.sh --create <repo-root> <area> <class> <issue link>        to start docs/mash/review-escapes.md, or"
        echo "  escape-add.sh --file <path> <repo-root> <area> <class> <issue link>   to keep it in another file."
        echo "A ledger the team shares counts everyone's entries; one in .gitignore holds only yours: offer to add it to .gitignore, and recommend committing it."
        echo "To keep another file, or none, for later sessions, add to .claude/settings.local.json (only you) or"
        echo "  .claude/settings.json (everyone):  {\"env\": {\"REVIEW_ROUTING_ESCAPES\": \"<path, or off>\"}}"
      } >&2
      exit 3 ;;
    *) exit "$status" ;;
  esac
fi
ledger_name="${ledger#"$root"/}"
mkdir -p "$(dirname "$ledger")"
if [[ ! -f "$ledger" ]]; then
  printf '%s\n\n%s\n%s\n\n' "# Review escapes" \
    "Bugs in code a review passed, found later by anyone (a person, CI or a later reviewer); one line per bug, keyed by its issue: date · area · class · link." \
    "The add-reviewer skill reads them through escapes-report.sh." > "$ledger"
fi
if [[ -f "$ledger" ]] && LINK="$link" awk -F ' · ' '{ field = $4; sub(/\r$/, "", field) } $1 ~ /^- [0-9][0-9][0-9][0-9]-/ && field == ENVIRON["LINK"] { found = 1 } END { exit !found }' "$ledger"; then
  echo "already recorded in $ledger_name: $link"
  exit 0
fi
if [[ -s "$ledger" && -n "$(tail -c1 "$ledger")" ]]; then printf '\n' >> "$ledger"; fi  # a file without a final newline
printf -- '- %s · %s · %s · %s\n' "$entry_date" "$area" "$class" "$link" >> "$ledger"
echo "recorded in $ledger_name: $area · $class"
report_line=$(REVIEW_ROUTING_ESCAPES="$ledger" bash "$(dirname "${BASH_SOURCE[0]}")/escapes-report.sh" "$root" --threshold 2 \
  | PREFIX="$area: " awk 'index($0, ENVIRON["PREFIX"]) == 1 && /-> add a reviewer for/')
if [[ -n "$report_line" ]]; then echo "$report_line"; fi
