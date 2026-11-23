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
#   mash-settings.sh toplevel <dir>               print the folder that holds the .git entry of <dir>'s repository
#   mash-settings.sh same-repository <dir>        exit 0 when the current folder (pwd -P) is in <dir>'s repository, else 6
#   mash-settings.sh private <dir> <name>         exit 0 when the home folder's file <name> is untracked and excluded, 1
#                                                 when untracked but not excluded yet, 6 when tracked or git cannot tell
# Environment variables: escapes = REVIEW_ROUTING_ESCAPES, backlog = MASH_WORKBENCH_BACKLOG; other keys have none.
#
# Outside a git repository every command exits 2, except get and source when the key's environment variable is set
# (they read it first). Callers such as escapes-path.sh then let the project folder stand in for the main worktree and read only
# the environment variable.
# Git starts only in a repository that a real .git entry names. Before any git process, the script walks up from
# <dir> in git's own order: the first folder with a .git entry is the repository; a folder shaped like a git directory
# (HEAD, plus objects, refs or commondir, each a file, a folder or a symbolic link, also a dangling one) with no .git
# entry gives exit 6. A commit can hold such a folder (only the
# name .git cannot be committed), and git would read its committed config, which can name a program to run
# (core.fsmonitor) or another top level (core.worktree). The git dir that git then reports must be the one that the
# .git entry names, or exit 6. A bare repository's own folder is refused this way too (exit 6); its linked worktrees
# give exit 5. Every git call runs without GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, the pathspec variables and the other
# variables that choose a repository, and with an empty core.fsmonitor (a second guard).
# The home folder must be the real folder <main>/.claude/mash-workbench: when .claude or .claude/mash-workbench is a
# symbolic link (also one that stays inside the repository), home, get (for the files), source, path, set and unset
# exit 6. A repository can commit a symbolic link, and it would move the settings and the review log to another place,
# or put a committed file where the private one is expected.
# set and unset take a lock (the folder .settings.lock in the home folder) around their read-modify-write; set --local
# adds the exclude line before it writes settings.local. A settings file that is a symbolic link is refused (exit 6) by
# get, source, path, set and unset. A submodule or a nested repository at .claude or .claude/mash-workbench (a .git
# entry there) is refused the same way. settings.local counts as the user's own file only when git answers that the
# main repository's index does not track .claude/mash-workbench/settings.local (any letter case), and the exclude line
# .claude/mash-workbench/settings.local is in the repository's info/exclude (set --local writes it; a patch or a clone
# cannot). The question names the git dir and the work folder, so git discovers no repository in a folder that a
# commit controls. Otherwise the file is read as a committed file (source prints team). set --local refuses to write
# a tracked file, or when git gives no answer, with the reason; it adds the exclude line otherwise.
# Exit codes: 0 success; 1 another set or unset holds the lock; 2 usage error, or <dir> is not in a git repository; 3 the key
# is not set anywhere, or its value is empty or only spaces and tabs; 5 a linked worktree of a bare repository, or the main worktree cannot be found from <dir>; 6 refused by a check (the
# line says why), also by every command but get and source with the key's environment variable set when <dir> is in
# a folder shaped like a git directory.
# Known limit: on a system that is not Windows, a drive-letter path (C:/x) is not absolute for the file tests, so
# check-escapes-path can answer "outside the repo" from one folder and "inside the repo" from another. No answer lets
# a committed file choose a place outside the repository. Git Bash is not tested.
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
    echo "       mash-settings.sh toplevel <dir>"
    echo "       mash-settings.sh same-repository <dir>"
    echo "       mash-settings.sh private <dir> <name>"
  } >&2
  exit 2
}
# warn <text>: one message on stderr, without control characters. A message can name a value, a path or a folder that a
# commit chose, and no escape sequence of it may reach the terminal or the session.
warn() { printf 'mash-settings: %s\n' "$*" | clean >&2; }
fail() {
  local code=$1
  shift
  warn "$*"
  exit "$code"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
is_absolute() { [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]; }

# run_git <arguments>: git without the environment variables that choose another repository, another index or another
# meaning for a pathspec, and without an fsmonitor program (an empty core.fsmonitor turns it off in every git version).
run_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_LITERAL_PATHSPECS -u GIT_GLOB_PATHSPECS \
    -u GIT_NOGLOB_PATHSPECS -u GIT_ICASE_PATHSPECS -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    GIT_NO_LAZY_FETCH=1 git -c core.fsmonitor= "$@"
}

# anchor <dir>: sets anchor_top (the folder that holds the .git entry) and anchor_git_dir (where that entry leads),
# before any git process starts. It walks up from <dir> in git's own order. A folder with a .git entry ends the walk.
# A folder shaped like a git directory (HEAD, plus objects, refs or commondir) with no .git entry is refused: git would
# take it as a repository, and a commit can hold such a folder, with a config that names a program to run. Returns 0,
# 2 (no repository) or 6 (refused), with the message on stderr.
anchor_top=""
anchor_git_dir=""
anchor() {
  local folder line target
  folder=$(cd "$1" && pwd -P) || return 2
  while :; do
    if [[ -e "$folder/.git" || -L "$folder/.git" ]]; then
      anchor_top=$folder
      anchor_git_dir=""
      if [[ -d "$folder/.git" ]] && [[ -e "$folder/.git/HEAD" || -L "$folder/.git/HEAD" ]] \
        && [[ ( -d "$folder/.git/objects" && -d "$folder/.git/refs" ) || -f "$folder/.git/commondir" ]]; then
        anchor_git_dir=$(cd "$folder/.git" && pwd -P) || return 2
      elif [[ -f "$folder/.git" ]]; then
        line=""
        IFS= read -r line < "$folder/.git" || true
        line=${line%$'\r'}
        if [[ "$line" == "gitdir: "* ]]; then
          target=${line#gitdir: }
          if ! is_absolute "$target"; then target="$folder/$target"; fi
          anchor_git_dir=$(cd "$target" 2>/dev/null && pwd -P) || anchor_git_dir=""
        fi
      fi
      # A .git entry that git cannot use (an empty folder, a folder without HEAD, objects and refs, a file with no
      # gitdir: line, a dangling link): git would go on to the folders above, which this walk has not checked.
      if [[ -z "$anchor_git_dir" ]]; then
        warn "refused: $folder/.git is a .git entry that git cannot use, so git would look for a repository in the folders above. Nothing ran."
        return 6
      fi
      return 0
    fi
    # -L too: git accepts a HEAD that is a symbolic link to refs/..., also a dangling one, which -e does not see.
    if [[ ( -e "$folder/HEAD" || -L "$folder/HEAD" ) && ( -e "$folder/objects" || -L "$folder/objects" || -e "$folder/refs" \
      || -L "$folder/refs" || -e "$folder/commondir" || -L "$folder/commondir" ) ]]; then
      warn "refused: $folder is shaped like a git directory and has no .git entry: a bare repository, or a folder that a commit can hold. Nothing ran. Run it from a work folder of the repository, or from a linked worktree."
      return 6
    fi
    if [[ "$folder" == / || "$folder" == "$(dirname "$folder")" ]]; then
      warn "not in a git repository: $1"
      return 2
    fi
    folder=$(dirname "$folder")
  done
}

# find_main <dir>: sets common (the shared git dir) and main (the main worktree, "" when it has none).
# Returns 0, 2 (not a repository), 5 (bare, or not findable) or 6 (refused by anchor), with the message on stderr.
common=""
main=""
main_unknown=""
find_main() {
  local dir=$1 out work_tree git_dir
  main=""
  main_unknown=""
  [[ -d "$dir" ]] || { warn "no such folder: $dir"; return 2; }
  anchor "$dir" || return $?
  # The scripts print the repository's paths in their messages: a folder name with a control character (a submodule
  # path can hold one) is refused, so no escape sequence of it reaches the terminal.
  if has_control "$anchor_top" || has_control "$anchor_git_dir"; then
    warn "refused: the path of the repository holds a control character: $anchor_top"
    return 6
  fi
  # Git runs only from the folder that holds the .git entry, and its answer must name that entry: then no committed
  # config chose the repository.
  dir=$anchor_top
  out=$(run_git -C "$dir" rev-parse --git-dir 2>/dev/null) || { warn "not in a git repository: $1"; return 2; }
  git_dir=$(cd "$dir" && cd "${out%$'\r'}" && pwd -P) || return 2
  if [[ "$git_dir" != "$anchor_git_dir" ]]; then
    warn "refused: git took the repository $git_dir, not the one that $dir/.git names. Nothing ran."
    return 6
  fi
  # Ask from the top level: git 2.7 to 2.12 print --git-common-dir relative to it, later versions relative to the
  # current folder, so both agree there.
  out=$(run_git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || { warn "not in a git repository: $1"; return 2; }
  common=$(cd "$dir" && cd "${out%$'\r'}" && pwd -P) || return 2
  # Submodules keep their work folder in core.worktree, relative to the git dir.
  work_tree=$(run_git --git-dir="$common" config core.worktree 2>/dev/null || true)
  work_tree=${work_tree%$'\r'}
  if [[ -n "$work_tree" ]]; then
    main=$(cd "$common" && cd "$work_tree" && pwd -P) || return 2
    if has_control "$main" || has_control "$common"; then warn "refused: the path of the repository holds a control character: $main"; return 6; fi
    return 0
  fi
  if [[ "$(run_git --git-dir="$common" rev-parse --is-bare-repository 2>/dev/null)" == true* ]]; then
    warn "bare repository: give the escapes path"
    return 5
  fi
  # The common git dir is named .git: its folder is the main worktree, from every worktree. This is also git's own
  # answer (the first line of git worktree list). A --separate-git-dir repository whose git folder is named .git (say
  # /store/proj/.git for the work folder /work/proj) gets /store/proj as git gives it: from a linked worktree nothing
  # records the work folder, so every worktree gives that same answer, and the settings never split in two.
  if [[ "$(basename "$common")" == .git ]]; then
    main=$(dirname "$common")
    if has_control "$main"; then warn "refused: the path of the repository holds a control character: $main"; return 6; fi
    return 0
  fi
  # Any other --separate-git-dir repository: only the work folder itself (the git dir and the common dir are the
  # same) can name its main worktree.
  if [[ "$git_dir" == "$common" ]]; then
    main=$dir
    return 0
  fi
  main_unknown=1
  warn "main worktree not found: set the escapes path with an absolute path"
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
  # A control character first: it would reach the terminal and the session in every message, also this one.
  has_control "$1" && fail 6 "refused: the path holds a control character"
  case "$1" in *\\*) fail 6 "refused: the path holds a backslash: write it with / (C:/Users/me/escapes): $1" ;; esac
  return 0
}
# clean: standard input without control characters (C0 but tab and line feed, DEL, and the C1 range as UTF-8): text
# that a commit can hold must not reach the terminal or the session as an escape sequence.
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177' | LC_ALL=C awk '{ gsub(/\302[\200-\237]/, ""); print }'; }
# has_control <text>: the text holds a character that clean removes, or a tab or a line feed. By bytes, so the answer
# is the same in every locale ([[:cntrl:]] misses C1 in the C locale).
# A tab or a line feed counts too: a path is one line of text.
has_control() { [[ "$1" == *$'\t'* || "$1" == *$'\n'* || "$(printf '%s' "$1" | clean)" != "$1" ]]; }
need_home() {
  local home_folder="$main/.claude/mash-workbench"
  local nested
  if [[ -L "$home_folder" ]]; then
    fail 6 "refused: $home_folder is a symbolic link: the home folder must be a real folder in the main worktree. Replace the link with a real folder (move its files into .claude/mash-workbench)."
  fi
  # The resolved place must be exactly <main>/.claude/mash-workbench: a .claude link that stays inside the repository
  # would put a committed folder there, and the exclude line would not cover the private file.
  if [[ -L "$main/.claude" || "$(normalize "$home_folder")" != "$(normalize "$main")/.claude/mash-workbench" ]]; then
    fail 6 "refused: $main/.claude is a symbolic link: the home folder must be the real folder .claude/mash-workbench in the main worktree. Replace the link with a real .claude folder (move the files it points to into it)."
  fi
  # A submodule or a nested repository: its files belong to another repository, and this repository's index does not
  # show them.
  for nested in "$main/.claude/.git" "$home_folder/.git"; do
    if [[ -e "$nested" || -L "$nested" ]]; then
      fail 6 "refused: $nested exists: .claude or .claude/mash-workbench is a submodule or a nested repository, so its files are not this clone's own. Keep the home folder as a plain folder of this repository."
    fi
  done
}

# refuse_linked_file <settings file>: exit 6 when it is a symbolic link. The file is never read or written through a
# link: a committed link to a private file would put that file's lines into the settings.
refuse_linked_file() {
  if [[ -L "$1" ]]; then fail 6 "refused: $1 is a symbolic link: a settings file must be a regular file"; fi
}
# local_state [name]: is the home folder's file <name> (default settings.local) the user's own? The question goes to
# the main repository's own index, with the git dir and the work folder named (no repository discovery in a folder
# that a commit controls). Returns 1 when git answers that the index tracks no such file (private, also when the home
# folder does not exist yet), 0 when it is tracked, and 2 when git gives no answer (git_error holds git's first line).
# Only 1 makes the file private.
git_error=""
local_state() {
  local status=0 output name=${1:-settings.local}
  [[ -d "$main/.claude/mash-workbench" ]] || return 1
  # :(icase): on a file system that ignores case, a tracked .Claude/Mash-Workbench/SETTINGS.LOCAL is the file that
  # gets opened.
  output=$(run_git --no-literal-pathspecs --git-dir="$common" --work-tree="$main" -C "$main" \
    ls-files --error-unmatch -- ":(icase).claude/mash-workbench/$name" 2>&1 >/dev/null) || status=$?
  case "$status" in
    0) return 0 ;;
    1) return 1 ;;
    *) git_error=${output%%$'\n'*}; return 2 ;;
  esac
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
  url=$(run_git -C "$dir" remote get-url origin 2>/dev/null || true)
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
        found_source="team"
        if [[ "$file" == settings.local ]]; then
          status=0
          local_state || status=$?
          # Untracked is not enough: a patch applied with git apply can create the file. The exclude line that
          # set --local writes marks the user's own: it is in the repository's own folder, which no commit, patch
          # or copied repository can write.
          if ((status == 1)) && has_line "$common/info/exclude" ".claude/mash-workbench/settings.local"; then
            found_source="local"
          fi
        fi
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
  if ((status == 2 || status == 6)); then need_main "$dir"; fi
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
  local dir=$1 key=$2 value=$3 scope=$4 mode=${5:-set} home file temporary exclude lock tries state
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
  if [[ "$scope" == --local ]]; then
    state=0
    local_state || state=$?
    case "$state" in
      0) fail 6 "refused: git tracks $file, so it is a committed file, not a private one. Remove it from the index first (git rm --cached .claude/mash-workbench/settings.local), then run this again" ;;
      2) fail 6 "refused: git could not tell whether $file is tracked ($git_error): nothing written" ;;
    esac
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
  if has_control "$path"; then echo "refused: the path holds a control character"; exit 6; fi
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
  done < <(run_git -C "$anchor_top" worktree list --porcelain 2>/dev/null || true)
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
    if [[ -n "$(run_git --literal-pathspecs -C "$main" ls-files -- "$relative" 2>/dev/null | head -1)" ]]; then
      echo "inside the repo: commit it to share with the team"
    elif run_git -C "$main" check-ignore -q -- "$relative" 2>/dev/null || run_git -C "$main" check-ignore -q -- "$relative/" 2>/dev/null; then
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
    key=$(repo_key "$anchor_top")
    if [[ -n "$owner" && "$(lower "$owner")" != "$key" ]]; then echo "refused: owned by $(printf '%s' "$owner" | clean)"; exit 6; fi
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
    printf '%s\n' "$found_value" | clean
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
  same-repository)
    # A write that an allow rule approves goes only to the session's own repository: <dir> must share its git dir with
    # the current folder (pwd -P: no variable can change it).
    [[ $# -eq 1 ]] || usage
    status=0
    find_main "$1" 2>/dev/null || status=$?
    if ((status != 0 && status != 5)); then need_main "$1"; fi  # prints why, and exits
    wanted=$common
    here_folder=$(pwd -P)
    status=0
    find_main "$here_folder" 2>/dev/null || status=$?
    if ((status != 0 && status != 5)) || [[ "$common" != "$wanted" ]]; then
      fail 6 "refused: the current folder ($here_folder) is not in the repository of $1: a write goes only to the repository the session works in. Run the command from inside that repository."
    fi
    ;;
  private)
    # private <dir> <name>: exit 0 when the home folder's file <name> is not tracked and its exclude line is in the
    # repository's info/exclude; 1 when it is not tracked but not excluded yet; 6 when it is tracked, or git gives no
    # answer.
    [[ $# -eq 2 ]] || usage
    [[ "$2" =~ ^[A-Za-z0-9._-]+$ && "$2" != . && "$2" != .. ]] || fail 2 "a file name in the home folder: $2"
    need_main "$1"
    need_home
    state=0
    local_state "$2" || state=$?
    case "$state" in
      0) fail 6 "refused: git tracks .claude/mash-workbench/$2, so it is a committed file, not private to this copy. Remove it from the index (git rm --cached .claude/mash-workbench/$2)." ;;
      2) fail 6 "refused: git could not tell whether .claude/mash-workbench/$2 is tracked ($git_error)" ;;
    esac
    has_line "$common/info/exclude" ".claude/mash-workbench/$2" || exit 1
    ;;
  toplevel)
    [[ $# -eq 1 ]] || usage
    status=0
    find_main "$1" 2>/dev/null || status=$?
    if ((status != 0 && status != 5)); then need_main "$1"; fi  # prints why, and exits
    printf '%s\n' "$anchor_top"
    ;;
  repo-key)
    [[ $# -eq 1 ]] || usage
    status=0
    find_main "$1" 2>/dev/null || status=$?
    if ((status == 2)); then exit 2; fi
    if ((status == 6)); then need_main "$1"; fi  # prints why, and exits
    repo_key "$anchor_top"
    ;;
  *) usage ;;
esac
