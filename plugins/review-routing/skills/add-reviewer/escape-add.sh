#!/usr/bin/env bash
set -euo pipefail
# Record a review escape: a bug in code a review passed, found later by anyone (a person, CI or a later reviewer).
# Each escape is one file, <escapes folder>/<date>-<slug>.md: frontmatter with date, area, class, and source when there
# is a link, an empty line, then the body (the conditions, the incorrect result, the expected result; its first line is the summary).
# escape-template.md shows one. escapes-path.sh says which folder, the same from every worktree; the folder holds a
# README.md whose repo: line names the owning repository (scripts/mash-settings.sh repo-key).
#
# Usage:
#   escape-add.sh <repo-root> <area> <class> <slug> --body <text> [--source <link>]
#       Record one escape. The body is the text itself (the conditions, the incorrect result, the expected result).
#       The script opens no file that an argument names and reads no standard input for one record: with an allow rule
#       it runs with no prompt, so it must not be able to copy a file (a private key, a .env) into the escapes folder.
#       The area is the directory a [[routes]] pattern would claim (src/payments), never a file;
#       the class and the slug are lowercase words joined by "-" (the slug at most 60 characters). The date is
#       ESCAPE_DATE or today in UTC; a name that exists, also in processed/, gets -2, -3 and so on. The same
#       area with the same source already in the folder (not in processed/) prints "already recorded: <file>"; a
#       GitHub /pull/N and /issues/N with no fragment count as the same source. When the area is at or over the threshold after the record, and
#       not declined, its escapes-report.sh line is printed too. The same source already recorded in another area is
#       still recorded (the report counts per area); "also recorded in <area>: <file>" follows the "recorded" line.
#   escape-add.sh --batch - <repo-root>
#       Record several, read from standard input (never from a file that an argument names): blocks separated by a line "---8<---", each an escape file's frontmatter (plus "slug:"; "date:"
#       and "source:" optional) and its body. Every block is checked first; one bad block writes nothing. Prints
#       "recorded N, already recorded M", then the threshold lines.
#   escape-add.sh --list <repo-root> <area>
#       Print "<file name>  <first body line>" for that area's escapes, newest first, at most 20, then "and N more".
#
# GitHub links are normalised: www., a ?query, a trailing / and a fragment are dropped, except a review comment
# (#discussion_r<id>, also spelled #r<id>), a #note_<id>, and on a pull request #issuecomment-<id> and
# #pullrequestreview-<id>; owner and repo are lowercased in /issues/N and /pull/N links; a pull request's /files,
# /changes, /commits or /checks page is the pull request; owner/repo#N and #N (owner/repo from
# the origin remote) become https://github.com/<owner>/<repo>/issues/N. Any other http(s) link only loses a trailing /.
#
# Exit codes: 0 recorded, already recorded, listed, or the ledger is off (escapes=off: nothing recorded); 2 usage error
# or a field that fails its check, or <repo-root> is not in a git repository (nothing written); 3 no escapes folder
# chosen yet, or an old one-file ledger is in use (the message says what to ask the user); 5 no main worktree (bare
# repository) and no absolute path set; 6 refused: the folder fails mash-settings.sh path or check-escapes-path (a
# linked worktree, a temporary folder, a folder another repository owns, a place outside the repository that the
# committed settings file chose, a symbolic link that leads out of the repository), the folder's README.md is a
# symbolic link, or this copy of the plugin is an old version in Claude Code's plugin cache (scripts/plugin-current.sh).
# Plain bash 3.2 (macOS) and Git Bash: no python3 (on Windows it is often the Microsoft Store stub); lowercase with tr.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bash "$here/../../scripts/plugin-current.sh" < /dev/null || exit $?
settings=$(cd "$here/../../scripts" && pwd -P)/mash-settings.sh
usage_text="usage: escape-add.sh <repo-root> <area> <class> <slug> --body <text> [--source <link>]
       escape-add.sh --batch - <repo-root>      (the blocks on standard input)
       escape-add.sh --list <repo-root> <area>"
refuse() { echo "escape-add: $*" >&2; echo "$usage_text" >&2; exit 2; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
quote() { printf '%q' "$1"; }  # a path in a printed command, safe to paste
tab=$'\t'

valid_date() {
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1
  local year=$((10#${BASH_REMATCH[1]})) month=$((10#${BASH_REMATCH[2]})) day=$((10#${BASH_REMATCH[3]})) last=31
  case "$month" in
    4 | 6 | 9 | 11) last=30 ;;
    2) if ((year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))); then last=29; else last=28; fi ;;
  esac
  ((year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= last))
}

# The checks set problem (why) and return 1, so --batch can name the block; they never exit.
problem=""
# check_area <area>: sets area_checked.
check_area() {
  local area=$1
  [[ "$area" != *$'\n'* && "$area" != *$'\r'* ]] || { problem="the area must be on one line"; return 1; }
  while [[ "$area" == ./* ]]; do area="${area#./}"; done
  while [[ "$area" == ?*/ ]]; do area="${area%/}"; done
  area=$(printf '%s' "$area" | tr -s '/')  # src//payments is src/payments
  [[ -n "$area" && "$area" != "." && "$area" != /* && "/$area/" != */../* ]] \
    || { problem="the area is a directory inside the repository, such as src/payments"; return 1; }
  [[ "$area" != *[[:space:]]* ]] || { problem="the area must not contain whitespace: $area"; return 1; }
  [[ ! -f "$root/$area" ]] || { problem="the area is a directory, not a file: use $(dirname "$area")"; return 1; }
  area_checked=$area
}
check_class() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { problem="the class is lowercase words joined by hyphens, such as wrong-result"; return 1; }
}
check_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#1} -le 60 ]] \
    || { problem="the slug is lowercase words joined by hyphens, at most 60 characters, such as discount-tax"; return 1; }
}
check_date() { valid_date "$1" || { problem="the date must be a real date, YYYY-MM-DD: $1"; return 1; }; }
# check_source <link>: sets source_checked to the normalised link.
check_source() {
  local link=$1 fragment="" origin owner_repo
  [[ -n "$link" ]] || { problem="the source link must not be empty"; return 1; }
  [[ "$link" != *$'\n'* && "$link" != *$'\r'* ]] || { problem="the source link must be on one line"; return 1; }
  while [[ "$link" == ?*/ ]]; do link="${link%/}"; done
  if [[ "$(lower "$link")" =~ ^(https?://(www\.)?github\.com/) ]]; then
    link="https://github.com/${link:${#BASH_REMATCH[1]}}"
    if [[ "$link" == *"#"* ]]; then fragment="#${link#*#}"; link="${link%%#*}"; fi
    link="${link%%\?*}"
    while [[ "$link" == ?*/ ]]; do link="${link%/}"; done
    # A pull request's files, changes, commits or checks page is the pull request.
    if [[ "$link" =~ ^(https://github\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+)/(files|changes|commits|checks)(/.*)?$ ]]; then
      link="${BASH_REMATCH[1]}"
    fi
    # A comment keeps its fragment: two comments on one pull request are two bugs. The files view spells a review
    # comment #r<id>. On a pull request, a conversation comment and a review are comments too; on an issue they are not
    # kept, so every spelling of the issue is one source.
    if [[ "$fragment" =~ ^#(discussion_)?r([0-9]+)$ ]]; then
      fragment="#discussion_r${BASH_REMATCH[2]}"
    elif [[ "$fragment" =~ ^#(issuecomment|pullrequestreview)-[0-9]+$ && "$link" =~ /pull/[0-9]+$ ]]; then
      :
    elif ! [[ "$fragment" =~ ^#note_[0-9]+$ ]]; then
      fragment=""
    fi
    if [[ "$link" =~ ^https://github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)$ ]]; then
      link="https://github.com/$(lower "${BASH_REMATCH[1]}")/$(lower "${BASH_REMATCH[2]}")/${BASH_REMATCH[3]}/${BASH_REMATCH[4]}"
    fi
    link="$link$fragment"
  elif [[ "$link" =~ ^([^/#[:space:]]+/[^/#[:space:]]+)#([0-9]+)$ ]]; then
    link="https://github.com/$(lower "${BASH_REMATCH[1]}")/issues/${BASH_REMATCH[2]}"
  elif [[ "$link" =~ ^#([0-9]+)$ ]]; then
    local number="${BASH_REMATCH[1]}"
    origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
    origin="${origin%$'\r'}"
    while [[ "$origin" == ?*/ ]]; do origin="${origin%/}"; done
    if [[ "$origin" =~ ^(https?://([^/@]+@)?|ssh://git@|git@)github\.com[:/]+([^/]+/[^/]+)$ ]]; then
      owner_repo="${BASH_REMATCH[3]%.git}"
      link="https://github.com/$(lower "$owner_repo")/issues/$number"
    else
      problem="cannot resolve $link: the origin remote is not a GitHub repository; give the full link"
      return 1
    fi
  fi
  [[ "$link" =~ ^https?://[^[:space:]]+$ ]] \
    || { problem="the source must be a GitHub issue, pull request or review comment, owner/repo#N, #N, or an http(s) link: $link"; return 1; }
  source_checked=$link
}
# normalize_body: stdin to stdout without \r, and without empty lines before the first and after the last real line.
normalize_body() {
  awk '{ sub(/\r$/, ""); lines[NR] = $0 }
    END {
      first = 1; while (first <= NR && lines[first] ~ /^[ \t]*$/) first++
      last = NR; while (last >= first && lines[last] ~ /^[ \t]*$/) last--
      for (i = first; i <= last; i++) print lines[i]
    }'
}

# set_root <dir>: root and main (the main worktree, "" in a bare repository). Recording needs git: the path checks and
# the owner marker come from it.
set_root() {
  local status=0
  [[ -d "$1" ]] || refuse "no such repository root: $1"
  root=$(cd "$1" && pwd -P)
  main=$(bash "$settings" main-worktree "$root" 2>/dev/null) || status=$?
  case "$status" in
    0) ;;
    5) main="" ;;
    *) echo "escape-add: not in a git repository: $root (escapes belong to a git repository)" >&2; exit 2 ;;
  esac
}
# display <path>: relative to the main worktree when inside it.
display() { if [[ -n "$main" && "$1" == "$main"/* ]]; then printf '%s' "${1#"$main"/}"; else printf '%s' "$1"; fi; }

setup_text() {
  {
    echo "no escapes folder chosen yet: ask the user where to keep it, then run"
    echo "  bash $(quote "$settings") set $(quote "$root") escapes <path, or off> --team   (committed escapes)"
    echo "  bash $(quote "$settings") set $(quote "$root") escapes <path, or off> --local  (excluded, or outside the repo)"
    echo "The default is .claude/mash-workbench/escapes; check a path first with: bash $(quote "$settings") check-escapes-path $(quote "$root") <path>"
    echo "Then follow \"Setting up escapes\" in the review-changes skill's reference.md: it offers the permission rules."
  } >&2
}

# resolve_folder record|list: sets folder, or exits with what the user must decide.
resolve_folder() {
  local mode=$1 status=0
  folder=$(bash "$here/escapes-path.sh" "$root") || status=$?
  case "$status" in
    0) ;;
    3) if [[ "$mode" == list ]]; then echo "no escapes in $list_area"; exit 0; fi; setup_text; exit 3 ;;
    4) if [[ "$mode" == list ]]; then echo "no escapes in $list_area"; exit 0; fi
      echo "the escapes ledger is off for this project: nothing recorded"; exit 0 ;;
    *) exit "$status" ;;
  esac
  if [[ -f "$folder" ]]; then
    echo "escape-add: old ledger format at $folder: ask the user, then run escape-migrate.sh" >&2
    exit 3
  fi
  [[ ! -e "$folder" || -d "$folder" ]] || { echo "escape-add: the escapes path is not a folder: $folder" >&2; exit 2; }
  if [[ ! -e "$folder" && "$(lower "$folder")" == *.md ]]; then
    echo "escape-add: this looks like an old ledger file: $folder; point the setting at a folder" >&2
    exit 2
  fi
}

# prepare_folder: the path check, then the folder and its README.md.
prepare_folder() {
  local message status=0 key
  message=$(bash "$settings" check-escapes-path "$root" "$folder" 2>&1) || status=$?
  if ((status != 0)); then echo "escape-add: $folder: $message" >&2; exit "$status"; fi
  mkdir -p "$folder"
  # Once more, now that the folder exists: every name on the path can be resolved.
  message=$(bash "$settings" check-escapes-path "$root" "$folder" 2>&1) || status=$?
  if ((status != 0)); then echo "escape-add: $folder: $message" >&2; exit "$status"; fi
  # A repository can commit a symbolic link: the README.md would be written where it points.
  if [[ -L "$folder/README.md" ]]; then echo "escape-add: $folder/README.md is a symbolic link: nothing recorded" >&2; exit 6; fi
  if [[ ! -f "$folder/README.md" ]]; then
    key=$(bash "$settings" repo-key "$root")
    printf '%s\n' "# Review escapes" "repo: $key" "" \
      "One file per bug that a review passed. The add-reviewer skill reads them through escapes-report.sh." > "$folder/README.md"
  fi
}

# escape_rows: escape-fields.awk over the folder's escape files (not README.md, not processed/, not a symbolic link:
# a repository can commit a link to a file elsewhere, and --list would print its first body line).
escape_rows() {
  local file
  local -a files=()
  for file in "$folder"/*.md; do
    if [[ -f "$file" && ! -L "$file" && "${file##*/}" != README.md ]]; then files+=("$file"); fi
  done
  if ((${#files[@]} > 0)); then awk -f "$here/escape-fields.awk" "${files[@]}"; fi
}

# write_escape <date> <area> <class> <slug> <source> <body>: sets written ("recorded" or "already"), written_file, and
# written_also (the first other area's file with the same source, as "<area>: <file>", or "").
write_escape() {
  local date=$1 area=$2 class=$3 slug=$4 source=$5 body=$6 name number=1 existing
  written_also=""
  if [[ -n "$source" ]]; then
    # Per area, as the report counts. A GitHub /pull/N and /issues/N with no fragment are the same number: an old
    # ledger wrote every pull request as /issues/N.
    local same=$source
    if [[ "$source" =~ ^(https://github\.com/[^/]+/[^/]+)/(pull|issues)/([0-9]+)$ ]]; then
      if [[ "${BASH_REMATCH[2]}" == pull ]]; then same="${BASH_REMATCH[1]}/issues/${BASH_REMATCH[3]}"; else same="${BASH_REMATCH[1]}/pull/${BASH_REMATCH[3]}"; fi
    fi
    existing=$(escape_rows | AREA="$area" SOURCE="$source" SAME="$same" \
      awk -F '\t' '$3 == ENVIRON["AREA"] && ($5 == ENVIRON["SOURCE"] || $5 == ENVIRON["SAME"]) { print $1; exit }')
    if [[ -n "$existing" ]]; then written=already; written_file="$folder/$existing"; return 0; fi
    existing=$(escape_rows | AREA="$area" SOURCE="$source" SAME="$same" \
      awk -F '\t' '$3 != ENVIRON["AREA"] && ($5 == ENVIRON["SOURCE"] || $5 == ENVIRON["SAME"]) { print $3 "\t" $1; exit }')
    if [[ -n "$existing" ]]; then written_also="${existing%%"$tab"*}: $(display "$folder/${existing#*"$tab"}")"; fi
  fi
  [[ -w "$folder" ]] || { echo "escape-add: cannot write in $folder" >&2; exit 2; }
  # noclobber claims the name in one step, so two sessions recording at once never share a file. A name in processed/
  # is not used again either, so moving files there never meets a clash.
  name="$date-$slug.md"
  until [[ ! -e "$folder/processed/$name" ]] && (set -o noclobber && : > "$folder/$name") 2>/dev/null; do
    number=$((number + 1))
    ((number < 1000)) || { echo "escape-add: cannot create $folder/$date-$slug.md" >&2; exit 2; }
    name="$date-$slug-$number.md"
  done
  {
    printf -- '---\ndate: %s\narea: %s\nclass: %s\n' "$date" "$area" "$class"
    if [[ -n "$source" ]]; then printf 'source: %s\n' "$source"; fi
    printf -- '---\n\n%s\n' "$body"  # the empty line is what prettier writes after frontmatter
  } > "$folder/$name"
  written=recorded
  written_file="$folder/$name"
}

# threshold_lines <area>...: the report line of each area at or over the threshold and not declined.
threshold_lines() {
  local report area
  report=$(bash "$here/escapes-report.sh" "$root" 2>/dev/null) || return 0
  for area in "$@"; do
    printf '%s\n' "$report" | PREFIX="$area: " awk 'index($0, ENVIRON["PREFIX"]) == 1 && /-> add a reviewer for/'
  done
}

default_date=${ESCAPE_DATE:-$(date -u +%F)}

[[ $# -ge 1 ]] || refuse "arguments needed"
case "$1" in
  --create | --file)
    refuse "$1 is gone: choose the escapes folder with bash $settings set <repo-root> escapes <folder> --team (or --local)" ;;
  --list)
    [[ $# -eq 3 ]] || refuse "--list needs <repo-root> <area>"
    set_root "$2"
    list_area=$3
    check_area "$list_area" || refuse "$problem"
    list_area=$area_checked
    resolve_folder list
    rows=$(escape_rows | AREA="$list_area" awk -F '\t' '$3 == ENVIRON["AREA"]' | sort -t "$tab" -k2,2r -k1,1r)
    if [[ -z "$rows" ]]; then echo "no escapes in $list_area"; exit 0; fi
    printf '%s\n' "$rows" | awk -F '\t' 'NR <= 20 { print $1 "  " $6 } END { if (NR > 20) print "and " NR - 20 " more" }'
    exit 0
    ;;
  --batch)
    [[ $# -eq 3 ]] || refuse "--batch needs - <repo-root>, with the blocks on standard input"
    [[ "$2" == - ]] || refuse "--batch reads the blocks from standard input only: pass - and send the text on standard input (a file that an argument names is never opened)"
    set_root "$3"
    check_date "$default_date" || refuse "ESCAPE_DATE: $problem"
    # Parse every block, then check every block; nothing is written until all pass.
    count=0; problems=""
    b_date=(); b_area=(); b_class=(); b_slug=(); b_source=(); b_body=(); b_problem=()
    start_block() { count=$((count + 1)); state=start; b_date[count]=""; b_area[count]=""; b_class[count]=""; b_slug[count]=""
      b_source[count]=""; b_body[count]=""; b_problem[count]=""; has_source[count]=""; }
    has_source=()
    start_block
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line%$'\r'}
      if [[ "$line" == "---8<---" ]]; then start_block; continue; fi
      case "$state" in
        start)
          if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
          if [[ "$line" == "---" ]]; then state=front; else b_problem[count]="it does not start with ---"; state=bad; fi ;;
        front)
          if [[ "$line" == "---" ]]; then state=body; continue; fi
          key=${line%%:*}; value=${line#*:}
          if [[ "$line" != *:* ]]; then b_problem[count]="a frontmatter line is not key: value: $line"; state=bad; continue; fi
          value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
          case "$key" in
            date) b_date[count]=$value ;;
            area) b_area[count]=$value ;;
            class) b_class[count]=$value ;;
            slug) b_slug[count]=$value ;;
            source) b_source[count]=$value; has_source[count]=1 ;;
            *) b_problem[count]="unknown frontmatter key: $key"; state=bad ;;
          esac ;;
        body) b_body[count]="${b_body[count]}$line"$'\n' ;;
        bad) ;;
      esac
    done
    blocks=0
    for ((index = 1; index <= count; index++)); do
      # A block with nothing in it (a trailing separator) is not a block.
      if [[ "$state" == start && $index -eq $count && -z "${b_problem[index]}" ]]; then continue; fi
      blocks=$((blocks + 1))
      message=${b_problem[index]}
      if [[ -z "$message" ]]; then
        b_body[index]=$(printf '%s' "${b_body[index]}" | normalize_body)
        if [[ -z "${b_date[index]}" ]]; then b_date[index]=$default_date; fi
        if ! check_date "${b_date[index]}"; then message=$problem
        elif [[ -z "${b_area[index]}" ]] || ! check_area "${b_area[index]}"; then message=${problem:-no area}
        elif ! check_class "${b_class[index]}"; then message=$problem
        elif ! check_slug "${b_slug[index]}"; then message=$problem
        elif [[ -n "${has_source[index]}" ]] && ! check_source "${b_source[index]}"; then message=$problem
        elif [[ -z "${b_body[index]//[[:space:]]/}" ]]; then message="the body needs at least one non-empty line"
        else
          b_area[index]=$area_checked
          if [[ -n "${has_source[index]}" ]]; then b_source[index]=$source_checked; fi
        fi
      fi
      problem=""
      if [[ -n "$message" ]]; then problems="${problems}escape-add: block $index: $message"$'\n'; b_problem[index]=$message; fi
    done
    if [[ -n "$problems" ]]; then printf '%s' "$problems" >&2; echo "nothing recorded" >&2; exit 2; fi
    if ((blocks == 0)); then refuse "the standard input holds no blocks"; fi
    resolve_folder record
    prepare_folder
    recorded=0; already=0; areas=(); also_lines=""
    for ((index = 1; index <= blocks; index++)); do
      write_escape "${b_date[index]}" "${b_area[index]}" "${b_class[index]}" "${b_slug[index]}" "${b_source[index]}" "${b_body[index]}"
      if [[ -n "$written_also" ]]; then also_lines="${also_lines}also recorded in $written_also"$'\n'; fi
      if [[ "$written" == recorded ]]; then
        recorded=$((recorded + 1))
        case " ${areas[*]-} " in *" ${b_area[index]} "*) ;; *) areas+=("${b_area[index]}") ;; esac
      else
        already=$((already + 1))
      fi
    done
    echo "recorded $recorded, already recorded $already"
    if [[ -n "$also_lines" ]]; then printf '%s' "$also_lines"; fi
    if ((${#areas[@]} > 0)); then threshold_lines "${areas[@]}"; fi
    exit 0
    ;;
esac

# One record.
positional=(); body_given=""; body_text=""; source_given=""; source=""
while (($# > 0)); do
  case "$1" in
    --body) (($# >= 2)) || refuse "--body needs the text"; body_text=$2; body_given=1; shift 2 ;;
    --body-file) refuse "--body-file is gone: pass the text itself with --body <text> (no file is opened, and no standard input is read)" ;;
    --source) (($# >= 2)) || refuse "--source needs a link"; source=$2; source_given=1; shift 2 ;;
    --*) refuse "unknown option: $1" ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -eq 4 ]] || refuse "four arguments needed: <repo-root> <area> <class> <slug>"
[[ -n "$body_given" ]] || refuse "--body is needed: the conditions, the incorrect result and the expected result"
set_root "${positional[0]}"
check_area "${positional[1]}" || refuse "$problem"
area=$area_checked
class=${positional[2]}
check_class "$class" || refuse "$problem"
check_slug "${positional[3]}" || refuse "$problem"
check_date "$default_date" || refuse "ESCAPE_DATE: $problem"
if [[ -n "$source_given" ]]; then check_source "$source" || refuse "$problem"; source=$source_checked; fi
[[ "$body_text" != - ]] || refuse "--body takes the text itself: standard input is not read (a redirect could copy a file)"
body=$(printf '%s\n' "$body_text" | normalize_body)
[[ -n "${body//[[:space:]]/}" ]] || refuse "the body needs at least one non-empty line"
resolve_folder record
prepare_folder
write_escape "$default_date" "$area" "$class" "${positional[3]}" "$source" "$body"
if [[ "$written" == already ]]; then echo "already recorded: $(display "$written_file")"; exit 0; fi
echo "recorded: $(display "$written_file")"
if [[ -n "$written_also" ]]; then echo "also recorded in $written_also"; fi
threshold_lines "$area"
