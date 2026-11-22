#!/usr/bin/env bash
set -euo pipefail
# Shared settings lookup and escapes-path check for the MASH plugins. Every worktree of a repository finds the same
# answer, because everything lives in the main worktree's home folder, <main>/.claude/mash-workbench/:
#   settings        key=value lines for the team (the user may commit it)
#   settings.local  key=value lines for this clone only (listed in the repository's info/exclude)
# The same file ships in every MASH plugin (tests/test_find_python.sh compares the copies).
#
# Usage:
#   mash-settings.sh main-worktree <dir>          print the main worktree's absolute path
#   mash-settings.sh home <dir>                   print <main>/.claude/mash-workbench (not created)
#   mash-settings.sh get <dir> <key>              print the value: environment variable, then settings.local, then settings
#                                                 (an empty or whitespace-only value counts as not set; set refuses one: use unset)
#                                                 A key repeated in one file: the last line wins, so a later empty line hides an
#                                                 earlier value in that file and the next source answers.
#   mash-settings.sh set <dir> <key> <value> --local|--team
#                                                 replace or append the key's line (--local: settings.local, --team: settings)
#   mash-settings.sh unset <dir> <key> --local|--team
#                                                 remove the key's lines from that file (a key not there is not an error)
#   mash-settings.sh source <dir> <key>           print where get's value comes from: env, local or team
#   mash-settings.sh path <dir> escapes|backlog   print the absolute path the key names (a relative value is from the main
#                                                 worktree), with . and .. removed as text. Exit 4 when the value is "off". Refused with exit 6: the
#                                                 repository root; a path outside the main worktree that the committed
#                                                 team file (settings) names, because only the user's own settings.local
#                                                 or the environment variable may choose a place outside the repository;
#                                                 a path written inside the main worktree that a symbolic link leads
#                                                 out of.
#   mash-settings.sh check-escapes-path <dir> <path>
#                                                 print one line with the consequence of keeping escapes at <path>
#   mash-settings.sh check-backlog-path <dir> <path>
#                                                 the same for the tooling backlog file (the owner is the file's repo: line)
#   mash-settings.sh repo-key <dir>               print host/owner/repo of the origin remote, or local/<folder>
# Environment variables: escapes = REVIEW_ROUTING_ESCAPES, backlog = MASH_WORKBENCH_BACKLOG; other keys have none.
#
# Outside a git repository every command exits 2, except get when the key's environment variable is set (get reads
# it first). Callers such as escapes-path.sh then let the project folder stand in for the main worktree and read only
# the environment variable.
# The home folder must be the real folder <main>/.claude/mash-workbench: when .claude or .claude/mash-workbench is a
# symbolic link (also one that stays inside the repository), home, get (for the files), source, path, set and unset
# exit 6. A repository can commit a symbolic link, and it would move the settings and the review log to another place,
# or put a committed file where the private one is expected.
# set and unset take a lock (the folder .settings.lock in the home folder) around their read-modify-write; set --local
# adds the exclude line before it writes settings.local. A settings file that is a symbolic link is refused (exit 6) by
# get, source, path, set and unset. settings.local counts as the user's own file only when git answers that it is not
# tracked: the question goes to git from the home folder itself, that folder must belong to this repository (not to
# a submodule or a nested repository), and the pathspec and index variables of the environment are not used. With any
# other answer, also a git error, the file is read as a committed file (source prints team), and set --local refuses
# to write it.
# Exit codes: 0 success; 1 another set or unset holds the lock; 2 usage error, or <dir> is not in a git repository; 3 the key
# is not set anywhere, or its value is empty or only spaces and tabs; 5 bare repository, or the main worktree cannot be found from <dir>; 6 refused by a check (the
# line says why).
# Needs git 2.7 or later: rev-parse runs from the top level, where git 2.7 to 2.12 and later versions print the same
# --git-common-dir. Plain bash 3.2 (macOS) and Git Bash: no associative arrays, no ${var,,}, no mapfile.

usage() {
  {
    echo "usage: mash-settings.sh main-worktree <dir>"
    echo "       mash-settings.sh home <dir>"
    echo "       mash-settings.sh get <dir> <key>"
    echo "       mash-settings.sh set <dir> <key> <value> --local|--team"
    echo "       mash-settings.sh unset <dir> <key> --local|--team"
    echo "       mash-settings.sh source <dir> <key>"
    echo "       mash-settings.sh path <dir> escapes|backlog"
    echo "       mash-settings.sh check-escapes-path <dir> <path>"
    echo "       mash-settings.sh check-backlog-path <dir> <path>"
    echo "       mash-settings.sh repo-key <dir>"
  } >&2
  exit 2
}
fail() {
  local code=$1
  shift
  echo "mash-settings: $*" >&2
  exit "$code"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
is_absolute() { [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]; }

# find_main <dir>: sets common (the shared git dir) and main (the main worktree, "" when it has none).
# Returns 0, 2 (not a repository) or 5 (bare, or not findable), with the message on stderr.
common=""
main=""
main_unknown=""
find_main() {
  local dir=$1 out work_tree git_dir
  main=""
  main_unknown=""
  [[ -d "$dir" ]] || { echo "mash-settings: no such folder: $dir" >&2; return 2; }
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "mash-settings: not in a git repository: $dir" >&2; return 2; }
  # Ask from the top level: git 2.7 to 2.12 print --git-common-dir relative to it, later versions relative to the
  # current folder, so both agree there. A bare repository has no top level; there <dir> is used.
  out=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "${out%$'\r'}" ]]; then dir=$(cd "${out%$'\r'}" && pwd -P) || return 2; fi
  out=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || { echo "mash-settings: not in a git repository: $dir" >&2; return 2; }
  common=$(cd "$dir" && cd "${out%$'\r'}" && pwd -P) || return 2
  # Submodules keep their work folder in core.worktree, relative to the git dir.
  work_tree=$(git --git-dir="$common" config core.worktree 2>/dev/null || true)
  work_tree=${work_tree%$'\r'}
  if [[ -n "$work_tree" ]]; then
    main=$(cd "$common" && cd "$work_tree" && pwd -P) || return 2
    return 0
  fi
  if [[ "$(git --git-dir="$common" rev-parse --is-bare-repository 2>/dev/null)" == true* ]]; then
    echo "mash-settings: bare repository: give the escapes path" >&2
    return 5
  fi
  if [[ "$(basename "$common")" == .git ]]; then
    main=$(dirname "$common")
    return 0
  fi
  # --separate-git-dir: the git dir is elsewhere and git does not record the work folder. Only the work folder itself
  # (where the git dir and the common dir are the same) can name it.
  out=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || return 2
  git_dir=$(cd "$dir" && cd "${out%$'\r'}" && pwd -P) || return 2
  if [[ "$git_dir" == "$common" ]] && out=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [[ -n "$out" ]]; then
    main=$(cd "${out%$'\r'}" && pwd -P) || return 2
    return 0
  fi
  main_unknown=1
  echo "mash-settings: main worktree not found: set the escapes path with an absolute path" >&2
  return 5
}

# need_main <dir>: find_main, exiting on any failure.
need_main() {
  local status=0
  find_main "$1" || status=$?
  if ((status != 0)); then exit "$status"; fi
}

env_name() {
  case "$1" in
    escapes) printf 'REVIEW_ROUTING_ESCAPES' ;;
    backlog) printf 'MASH_WORKBENCH_BACKLOG' ;;
  esac
}

# read_key <file> <key>: print the last value of <key>; exit 1 when absent. Keys are compared whole, never as patterns.
read_key() {
  KEY="$2" awk '
    { sub(/\r$/, "") }
    $0 == "" || /^#/ { next }
    {
      split_at = index($0, "=")
      if (split_at > 0 && substr($0, 1, split_at - 1) == ENVIRON["KEY"]) { value = substr($0, split_at + 1); found = 1 }
    }
    END { if (found) print value; exit !found }' "$1"
}

# has_line <file> <line>: the file holds that exact line (a trailing \r ignored).
has_line() { [[ -f "$1" ]] && LINE="$2" awk '{ sub(/\r$/, "") } $0 == ENVIRON["LINE"] { found = 1 } END { exit !found }' "$1"; }

# append_line <file> <line>: add it on its own row, also when the file has no final newline.
append_line() {
  if [[ -s "$1" && -n "$(tail -c1 "$1")" ]]; then printf '\n' >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}

# normalize <path>: an absolute path with symlinks resolved in its existing part and . and .. removed.
normalize() {
  local path=$1 rest="" parent
  while [[ ! -d "$path" ]]; do
    parent=$(dirname "$path")
    rest="$(basename "$path")${rest:+/$rest}"
    [[ "$parent" != "$path" ]] || break
    path=$parent
  done
  if [[ -d "$path" ]]; then path=$(cd "$path" && pwd -P); fi
  squash "$path${rest:+/$rest}"
}
# squash <path>: the path as written, with . and .. and doubled slashes removed; no symbolic link is resolved.
squash() {
  local joined=$1 part count=0 index result="" drive=""
  local -a parts stack
  # A drive letter (C:/Users/me) stays in front as written: the result is C:/Users/me, not /C:/Users/me.
  if [[ "$joined" =~ ^[A-Za-z]:/ ]]; then drive=${joined:0:2}; joined=${joined:2}; fi
  IFS=/ read -r -a parts <<< "$joined"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..) if ((count > 0)); then count=$((count - 1)); fi ;;
      *) stack[count]=$part; count=$((count + 1)) ;;
    esac
  done
  for ((index = 0; index < count; index++)); do result="$result/${stack[index]}"; done
  printf '%s%s' "$drive" "${result:-/}"
}

# under <path> <folder>: <path> is <folder> or inside it.
under() {
  local folder=${2%/}
  [[ -z "$folder" || "$1" == "$folder" || "$1" == "$folder"/* ]]
}

# need_home: the home folder is a real folder inside the main worktree, or exit 6 (see the header).
# refuse_backslash <path>: the path code splits on "/" only, so a name with "\" would pass as one name in a folder
# while Git Bash reads it as a path.
refuse_backslash() {
  case "$1" in *\\*) fail 6 "refused: the path holds a backslash: write it with / (C:/Users/me/escapes): $1" ;; esac
}
need_home() {
  local home_folder="$main/.claude/mash-workbench"
  if [[ -L "$home_folder" ]]; then
    fail 6 "refused: $home_folder is a symbolic link: the home folder must be a real folder in the main worktree"
  fi
  # The resolved place must be exactly <main>/.claude/mash-workbench: a .claude link that stays inside the repository
  # would put a committed folder there.
  if [[ -L "$main/.claude" || "$(normalize "$home_folder")" != "$(normalize "$main")/.claude/mash-workbench" ]]; then
    fail 6 "refused: $main/.claude is a symbolic link: the home folder must be the real folder .claude/mash-workbench in the main worktree"
  fi
}

# refuse_linked_file <settings file>: exit 6 when it is a symbolic link. The file is never read or written through a
# link: a committed link to a private file would put that file's lines into the settings.
refuse_linked_file() {
  if [[ -L "$1" ]]; then fail 6 "refused: $1 is a symbolic link: a settings file must be a regular file"; fi
}
# home_git <git arguments>: git in the home folder, without the pathspec and index variables of the environment (they
# would change what "tracked" means).
home_git() {
  env -u GIT_LITERAL_PATHSPECS -u GIT_GLOB_PATHSPECS -u GIT_NOGLOB_PATHSPECS -u GIT_ICASE_PATHSPECS -u GIT_INDEX_FILE \
    git --no-literal-pathspecs -C "$main/.claude/mash-workbench" "$@"
}
# local_is_tracked: settings.local is not surely the user's own file. It returns 1 (private) only on a positive
# answer: the home folder does not exist yet, or it belongs to this repository and git says that it tracks no
# settings.local there. A submodule or a nested repository as the home folder, a tracked file and a git error all
# return 0.
local_is_tracked() {
  local top status=0
  [[ -d "$main/.claude/mash-workbench" ]] || return 1
  top=$(home_git rev-parse --show-toplevel 2>/dev/null) || return 0
  top=$(cd "${top%$'\r'}" 2>/dev/null && pwd -P) || return 0
  [[ "$top" == "$(normalize "$main")" ]] || return 0
  # :(icase): on a file system that ignores case, a tracked SETTINGS.LOCAL is the file that gets opened.
  home_git ls-files --error-unmatch -- ':(icase)settings.local' >/dev/null 2>&1 || status=$?
  # 1 is git's "no such tracked file"; 0 is tracked; any other code is an error, which is not a "no".
  ((status != 1))
}

# leaves_repository <absolute path>: the path is written inside the main worktree, and a symbolic link on it leads out.
leaves_repository() {
  local written real main_real
  [[ -n "$main" ]] || return 1
  main_real=$(normalize "$main")
  written=$(squash "$1")
  real=$(normalize "$1")
  { under "$written" "$main" || under "$written" "$main_real"; } && ! under "$real" "$main_real"
}

repo_key() {
  local dir=$1 url host_part rest host after name
  url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  url=${url%$'\r'}
  # A remote that is a path on this machine is no name for the repository, and the key goes into committed files.
  case "$url" in /* | .* | "~"* | file://* | [A-Za-z]:[/\\]*) url="" ;; esac
  if [[ -z "$url" ]]; then
    if [[ -n "$main" ]]; then name=$(basename "$main"); else name=$(basename "$common" .git); fi
    printf 'local/%s\n' "$(lower "$name")"
    return
  fi
  local had_scheme=""
  if [[ "$url" == *://* ]]; then url=${url#*://}; had_scheme=1; fi
  host_part=${url%%/*}
  rest=${url#"$host_part"}
  host_part=${host_part##*@}  # credentials end at the last @ before the host
  if [[ "$host_part" == *:* ]]; then
    host=${host_part%%:*}
    after=${host_part#*:}
    if [[ -n "$had_scheme" && "$after" =~ ^[0-9]*$ ]]; then host_part=$host; else host_part="$host/$after"; fi
  fi
  url="$host_part$rest"
  local double=// single=/
  while [[ "$url" == *//* ]]; do url=${url//$double/$single}; done  # git@host:/srv/x and ssh://git@host/srv/x agree
  while [[ "$url" == ?*/ ]]; do url=${url%/}; done
  url=${url%.git}
  printf '%s\n' "$(lower "$url")"
}

# lookup <dir> <key>: sets found_value and found_source (env, local or team), or exits 3 when the key is not set.
found_value=""
found_source=""
lookup() {
  local dir=$1 key=$2 variable value file status=0
  variable=$(env_name "$key")
  if [[ -n "$variable" ]]; then
    value=${!variable:-}
    if [[ -n "${value//[[:space:]]/}" ]]; then found_value=$value; found_source="env"; return 0; fi
  fi
  need_main "$dir"
  need_home
  for file in settings.local settings; do
    refuse_linked_file "$main/.claude/mash-workbench/$file"
    if [[ -f "$main/.claude/mash-workbench/$file" ]]; then
      status=0
      value=$(read_key "$main/.claude/mash-workbench/$file" "$key") || status=$?
      # An empty value, or one of only spaces and tabs, counts as not set: the next source answers.
      if ((status == 0)) && [[ -n "${value//[[:space:]]/}" ]]; then
        found_value=$value
        # settings.local is the user's own file only when git does not track it: a repository can commit one.
        if [[ "$file" == settings ]] || local_is_tracked; then found_source="team"; else found_source="local"; fi
        return 0
      fi
    fi
  done
  exit 3
}

# command_path <dir> <key>: see the header.
command_path() {
  local dir=$1 key=$2 status=0 path noun
  case "$key" in
    escapes) noun="escapes folder" ;;
    backlog) noun="backlog file" ;;
    *) usage ;;
  esac
  lookup "$dir" "$key"
  if [[ "$found_value" == off ]]; then exit 4; fi
  path=$found_value
  refuse_backslash "$path"
  if [[ "$found_source" == env ]]; then find_main "$dir" 2>/dev/null || status=$?; fi
  if ((status == 2)); then need_main "$dir"; fi
  if ! is_absolute "$path"; then
    [[ -n "$main" ]] || fail 5 "the $key setting is relative, but no main worktree was found: set it to an absolute path"
    path="$main/$path"
  fi
  # No ".." after this line: the text that is checked is the text that is printed and written. Otherwise
  # "<no such name>/../<link>" would pass as text while the write follows the link.
  path=$(squash "$path")
  if [[ -n "$main" ]]; then
    if [[ "$(normalize "$path")" == "$(normalize "$main")" ]]; then fail 6 "refused: the $noun must not be the repository root"; fi
    if leaves_repository "$path"; then
      fail 6 "refused: a symbolic link on $path leads outside the repository. If the user wants that place, name it directly: mash-settings.sh set <dir> $key <the real path> --local"
    fi
    # A link to a file, or a dangling link: the checks above resolve folders only, and a read or a write would follow it.
    if [[ -L "$path" && ! -d "$path" ]]; then fail 6 "refused: $path is a symbolic link"; fi
    if [[ "$found_source" == team ]] && ! under "$(normalize "$path")" "$(normalize "$main")"; then
      fail 6 "refused: the committed settings file puts the $noun outside the repository: $path. A committed file cannot choose that. Ask the user; on a yes, run: mash-settings.sh set <dir> $key $(printf '%q' "$found_value") --local"
    fi
  fi
  printf '%s\n' "$path"
}

# command_set <dir> <key> <value> <scope> [unset]: replace or append the key's line; with "unset", remove its lines.
command_set() {
  local dir=$1 key=$2 value=$3 scope=$4 mode=${5:-set} home file temporary exclude lock tries
  local line=".claude/mash-workbench/settings.local"
  [[ -n "$key" && "$key" != *=* && "$key" != \#* && "$key" != *$'\n'* && "$key" != *$'\r'* ]] \
    || fail 2 "a key is not empty, holds no = and no line break, and does not start with #: $key"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail 2 "the value must be on one line"
  if [[ "$mode" == set && -z "${value//[[:space:]]/}" ]]; then fail 2 "the value is empty: an empty value counts as not set; use unset <dir> <key> --local|--team"; fi
  case "$scope" in
    --local) file=settings.local ;;
    --team) file=settings ;;
    *) usage ;;
  esac
  need_main "$dir"
  need_home
  home="$main/.claude/mash-workbench"
  file="$home/$file"
  refuse_linked_file "$home/settings"
  refuse_linked_file "$home/settings.local"
  if [[ "$scope" == --local ]] && local_is_tracked; then
    fail 6 "refused: $file is not a private file: git tracks it, or its folder belongs to another repository (a submodule). Remove it from the index first (git rm --cached), then run this again"
  fi
  if [[ "$mode" == unset && ! -f "$file" ]]; then printf '%s was not set in %s\n' "$key" "$file"; return 0; fi
  mkdir -p "$home"
  if [[ "$scope" == --local && "$mode" == set ]]; then
    # The exclude line comes first, so the private file never shows up as untracked, even for a moment.
    # Always the common git dir's exclude file: in submodules and --separate-git-dir repos, <main>/.git is a file.
    exclude="$common/info/exclude"
    mkdir -p "$common/info"
    has_line "$exclude" "$line" || append_line "$exclude" "$line"
  fi
  # One writer at a time: mkdir is atomic everywhere (macOS, Linux, Git Bash). Wait about 2 seconds, then give up.
  lock="$home/.settings.lock"
  tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if ((tries > 20)); then
      fail 1 "another mash-settings.sh is writing in $home; if none is running, remove $lock"
    fi
    sleep 0.1
  done
  # Rewrite through a temporary file in the same folder, so the mv replaces the file in one step. Not mktemp: its
  # 0600 would replace the file's mode. cp -p copies the old mode (portable, unlike stat flags); the redirection
  # below keeps it, and a new file gets the umask mode.
  temporary="$home/.settings.$$.tmp"
  rm -f "$temporary"
  trap 'rm -f "$temporary"; rmdir "$lock" 2>/dev/null || true' EXIT
  if [[ -f "$file" ]]; then
    cp -p "$file" "$temporary"
    KEY="$key" VALUE="$value" MODE="$mode" awk '
      {
        line = $0; sub(/\r$/, "", line)
        split_at = index(line, "=")
        if (line !~ /^#/ && split_at > 0 && substr(line, 1, split_at - 1) == ENVIRON["KEY"]) {
          if (!done && ENVIRON["MODE"] == "set") print ENVIRON["KEY"] "=" ENVIRON["VALUE"]
          done = 1
          next
        }
        print
      }
      END { if (!done && ENVIRON["MODE"] == "set") print ENVIRON["KEY"] "=" ENVIRON["VALUE"] }' "$file" > "$temporary"
  else
    printf '%s=%s\n' "$key" "$value" > "$temporary"
  fi
  mv "$temporary" "$file"
  rmdir "$lock"
  trap - EXIT
  printf '%s %s in %s\n' "$mode" "$key" "$file"
}

# command_check <dir> <path> <kind>: kind is escapes (a folder) or backlog (a file).
command_check() {
  local dir=$1 path=$2 kind=$3 noun="escapes folder" status=0 target worktree first=1 home relative owner key temporary_root owner_file
  if [[ "$kind" == backlog ]]; then noun="backlog file"; fi
  case "$path" in *\\*) echo "refused: the path holds a backslash: write it with /"; exit 6 ;; esac
  find_main "$dir" 2>/dev/null || status=$?
  case "$status" in
    0) ;;
    5) # An absolute path can still be checked; a relative one has nothing to be relative to.
      is_absolute "$path" || fail 5 "no main worktree (bare repository, or a linked worktree of a --separate-git-dir repository): give an absolute path" ;;
    *) need_main "$dir" ;;  # prints why, and exits
  esac
  if ! is_absolute "$path"; then path="$main/$path"; fi
  path=$(squash "$path")  # see command_path: ".." is removed before any check
  target=$(normalize "$path")
  if [[ -n "$main" && "$target" == "$(normalize "$main")" ]]; then echo "refused: the $noun must not be the repository root"; exit 6; fi
  if leaves_repository "$path"; then echo "refused: a symbolic link on this path leads outside the repository: name the real place instead"; exit 6; fi
  # A link that normalize left in place is dangling or names a file: a write would follow it.
  if [[ -L "$target" ]]; then echo "refused: the $noun is a symbolic link"; exit 6; fi
  if [[ "$kind" == backlog && -d "$target" ]]; then echo "refused: the backlog path is a folder: name a file"; exit 6; fi
  # 1. A linked worktree (every entry but the first, which is the main worktree or the bare git dir).
  while IFS= read -r worktree; do
    worktree=${worktree%$'\r'}
    [[ "$worktree" == "worktree "* ]] || continue
    if ((first)); then first=0; continue; fi
    worktree=$(normalize "${worktree#worktree }")
    if under "$target" "$worktree"; then echo "refused: a linked worktree is deleted with its branch"; exit 6; fi
  done < <(git -C "$dir" worktree list --porcelain 2>/dev/null || true)
  # The git directory: nothing in it is committed or shared.
  if under "$target" "$common"; then echo "refused: inside the git directory: cannot be committed or shared"; exit 6; fi
  # 2. Temporary folders: /tmp, /private/tmp, $TMPDIR, and the Claude Code scratchpad (/claude-<digits>/) under them.
  # A root that resolves to / is skipped: it would refuse every path.
  for temporary_root in /tmp /private/tmp /var/tmp /private/var/tmp "${TMPDIR:-}"; do
    [[ -n "$temporary_root" ]] || continue
    temporary_root=$(normalize "$temporary_root")
    [[ "$temporary_root" != / ]] || continue
    if under "$target" "$temporary_root"; then
      if [[ "${target#"$temporary_root"}/" =~ /claude-[0-9]+/ ]]; then
        echo "refused: the Claude Code scratchpad is deleted with the session"
      else
        echo "refused: a temporary folder is deleted on reboot or cleanup"
      fi
      exit 6
    fi
  done
  # 3. Inside the main worktree.
  if [[ -n "$main" ]] && under "$target" "$main"; then
    relative=${target#"$main"}
    relative=${relative#/}
    relative=${relative:-.}
    if [[ -n "$(git --literal-pathspecs -C "$main" ls-files -- "$relative" 2>/dev/null | head -1)" ]]; then
      echo "inside the repo: commit it to share with the team"
    elif git -C "$main" check-ignore -q -- "$relative" 2>/dev/null || git -C "$main" check-ignore -q -- "$relative/" 2>/dev/null; then
      echo "inside the repo, ignored: private to this clone"
    else
      echo "inside the repo: commit it to share with the team"
    fi
    exit 0
  fi
  # 6. Outside the repo, the folder's README.md (for the backlog, the file itself) names its owning repository.
  owner_file="$target/README.md"
  if [[ "$kind" == backlog ]]; then owner_file=$target; fi
  if [[ -f "$owner_file" ]]; then
    owner=$(awk '{ sub(/\r$/, "") } /^repo:/ { sub(/^repo:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$owner_file")
    key=$(repo_key "$dir")
    if [[ -n "$owner" && "$(lower "$owner")" != "$key" ]]; then echo "refused: owned by $owner"; exit 6; fi
  fi
  # A linked worktree of a --separate-git-dir repository: the main work folder exists but git does not name it.
  if [[ -n "$main_unknown" ]]; then
    echo "main worktree unknown: cannot tell if this path is inside the repo"
    exit 0
  fi
  # 4 and 5.
  home=""
  if [[ -n "${HOME:-}" ]]; then home=$(normalize "$HOME"); fi
  if [[ -n "$home" && "$home" != / ]] && under "$target" "$home"; then
    # shellcheck disable=SC2016  # $HOME is meant literally
    echo 'outside the repo: survives deleting the clone; in a container it is lost on rebuild unless $HOME is mounted'
  else
    echo "outside the repo"
  fi
}

[[ $# -ge 1 ]] || usage
command=$1
shift
case "$command" in
  main-worktree)
    [[ $# -eq 1 ]] || usage
    need_main "$1"
    [[ -n "$main" ]] || exit 5
    printf '%s\n' "$main"
    ;;
  home)
    [[ $# -eq 1 ]] || usage
    need_main "$1"
    need_home
    printf '%s\n' "$main/.claude/mash-workbench"
    ;;
  get)
    [[ $# -eq 2 ]] || usage
    lookup "$1" "$2"
    printf '%s\n' "$found_value"
    ;;
  source)
    [[ $# -eq 2 ]] || usage
    lookup "$1" "$2"
    printf '%s\n' "$found_source"
    ;;
  path)
    [[ $# -eq 2 ]] || usage
    command_path "$1" "$2"
    ;;
  set)
    [[ $# -eq 4 ]] || usage
    command_set "$1" "$2" "$3" "$4"
    ;;
  unset)
    [[ $# -eq 3 ]] || usage
    command_set "$1" "$2" "" "$3" unset
    ;;
  check-escapes-path)
    [[ $# -eq 2 ]] || usage
    command_check "$1" "$2" escapes
    ;;
  check-backlog-path)
    [[ $# -eq 2 ]] || usage
    command_check "$1" "$2" backlog
    ;;
  repo-key)
    [[ $# -eq 1 ]] || usage
    status=0
    find_main "$1" 2>/dev/null || status=$?
    if ((status == 2)); then exit 2; fi
    repo_key "$1"
    ;;
  *) usage ;;
esac
