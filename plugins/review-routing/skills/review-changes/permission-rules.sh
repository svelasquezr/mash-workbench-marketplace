#!/usr/bin/env bash
# Print the Claude Code allow rules that let a session with no user (claude -p in a linked worktree) run this plugin's
# recording scripts without a prompt, and name the old rules to remove. It only prints: the user decides, and the
# session edits the settings file with its edit tool, so Claude Code asks the user to approve that write.
# The same file ships in review-routing (skills/review-changes/) and in mash-workbench (skills/scout/); the folder it
# is in says which plugin's rules it prints (tests/test_permission_rules.sh compares the copies).
#
# Usage: permission-rules.sh <repo-root>
#
# Output, one item per line:
#   file: <path>      a .claude/settings.local.json: first the main worktree's (where the rules go), then, from a
#                     linked worktree that has its own file with rules to remove, that file. The lines below a
#                     "file:" line are about that file.
#   present: <rule>   a current rule that the file's allow list already holds
#   add: <rule>       a current rule that the allow list does not hold. No "add:" line is printed while a "remove:"
#                     line is: the old rules go first, then this script offers the new ones.
#   remove: <rule>    a "Bash(bash ...)" rule in an allow list that is not a current rule and names one of this
#                     plugin's scripts, either under a folder with the plugin's name (a rule for another plugin
#                     version: it still approves that version's scripts, which stay in Claude Code's plugin cache)
#                     or after a wildcard. The rules of review-routing 0.4.0 to 0.5.0 started with a wildcard
#                     ("Bash(bash */review-routing/*add-reviewer/escape-add.sh*)"), and "*" matches any text, spaces
#                     too, so they allowed any command that mentions the script's name. A rule for a script of the
#                     same name elsewhere, with an exact path, is left alone.
#   note: <text>      what to do with the lines above
#
# The rules. Claude Code compares a rule with the command text letter for letter, and a rule is safe only when
# nothing but the arguments can vary. So each rule is "Bash(bash <script path> *)": the exact path of this installed
# copy, and one wildcard, at the end. There is one rule for each spelling a skill writes ("<skills>/record-escape/../
# add-reviewer/escape-add.sh" and "<skills>/add-reviewer/escape-add.sh" are two texts), for the scripts a session
# with no user needs: escape-add.sh and review-log.sh in review-routing, backlog-add.sh in mash-workbench. The steps
# that need a user's answer first (escape-migrate.sh, mash-settings.sh set) get no rule. A path with a space is
# spelled in double quotes, as a session must write it.
# The path holds the plugin's version folder, so the rules stop matching after a plugin update, on purpose: run
# this script again, remove the old rules, run it once more and add the new ones. The old rules must go: they keep
# approving the old version's scripts. (From this version on, those scripts also refuse to run from an old copy:
# scripts/plugin-current.sh.)
# What a rule still allows: any arguments to that one script. The scripts open no file that an argument names.
# <repo-root> is an argument, but the writing scripts refuse one that is not in the repository of the current folder
# (mash-settings.sh same-repository), and Claude Code blocks a cd out of the session's folders.
#
# Reads: the two settings.local.json files named above, only the "Bash(...)" strings of their arrays, with the name of
# each array (allow, deny, ask). A rule in a deny or ask list is never printed as "present" or "remove"; a current
# rule that is also in one gets a note, because a deny or ask rule wins. Writes nothing. No network.
# Exit codes: 0 success; 2 usage error, or <repo-root> is not in a git repository; 5 a linked worktree of a bare repository, or the main
# worktree cannot be found; 6 no rules offered: the plugin folder, or a symbolic link on the path to it, is inside a
# worktree of the repository (a session that edits files there could change the scripts, or point the link at other
# scripts, and then run them with no prompt), or the path holds a character that a rule cannot spell safely (anything
# but letters, digits, space and _ . / : @ % + = , ~ -).
# Plain bash 3.2 (macOS) and Git Bash: no associative arrays, no ${var,,}, no mapfile.
set -euo pipefail
# Exit 6 also when <repo-root> is in a folder shaped like a git directory (mash-settings.sh refuses it before git runs).
# Git runs without the variables that choose another repository, index or config, and with no fsmonitor program
# (GIT_CONFIG_COUNT needs version 2.31 or later; an older version ignores it).
# In a partial clone it downloads no missing object (GIT_NO_LAZY_FETCH, version 2.44 and later; an older version can
# download one, which is a network call).
# Each git call runs in a folder that mash-settings.sh checked: the main worktree, or the top folder of <repo-root>
# (mash-settings.sh toplevel), with -C.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_NAMESPACE GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS GIT_CONFIG_PARAMETERS
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='' GIT_NO_LAZY_FETCH=1

usage="usage: permission-rules.sh <repo-root>"
[[ $# -eq 1 && -d "$1" ]] || { echo "$usage" >&2; exit 2; }
fail() {
  local code=$1
  shift
  echo "permission-rules: $*" >&2
  exit "$code"
}

# The skill's base directory as the session wrote it: the rules must repeat that text. A relative path, or one with
# "." or ".." in it, is resolved (logically: a symlink in the path stays as written).
here=$(dirname "${BASH_SOURCE[0]}")
case "$here" in
  /*) case "$here/" in */./* | */../* | *//*) here=$(cd "$here" && pwd) ;; esac ;;
  *) here=$(cd "$here" && pwd) ;;
esac
# Which plugin: the skill folder this copy is in. plugin_name is the folder name that an installed copy has on its
# path; our_scripts are the scripts that have, or had, a rule; named_only are scripts that count as ours only under a
# folder with the plugin's name (the name is too common after a bare wildcard).
case "$here" in
  */skills/review-changes)
    plugin_name=review-routing
    spellings="add-reviewer/escape-add.sh review-changes/../add-reviewer/escape-add.sh record-escape/../add-reviewer/escape-add.sh review-changes/review-log.sh record-escape/../review-changes/review-log.sh"
    our_scripts="escape-add.sh escape-migrate.sh review-log.sh"
    named_only="mash-settings.sh"
    ;;
  */skills/scout)
    plugin_name=mash-workbench
    spellings="scout/backlog-add.sh"
    our_scripts="backlog-add.sh"
    named_only=""
    ;;
  *) fail 6 "not in a plugin's skills/review-changes or skills/scout folder: $here" ;;
esac
skills=$(dirname "$here")

safe_path='^[A-Za-z0-9 _./:@%+=,~-]+$'
[[ "$skills" =~ $safe_path ]] || fail 6 "no rules offered: the plugin path holds a character that a rule cannot spell safely: $skills"

root=$(cd "$1" && pwd -P)
main=$(bash "$here/../../scripts/mash-settings.sh" main-worktree "$root") || exit $?
root=$(bash "$here/../../scripts/mash-settings.sh" toplevel "$root") || exit $?
main=$(cd "$main" && pwd -P)
# The folders a session of this repository edits: the main worktree, <repo-root> and every linked worktree. A listed
# worktree whose folder is gone (deleted by hand, not pruned yet) counts as git names it.
repo_folders=$(
  printf '%s\n%s\n' "$main" "$root"
  { git -C "$root" worktree list --porcelain 2>/dev/null || true; } | tr -d '\r' | sed -n 's/^worktree //p' | while IFS= read -r folder; do
    if [[ -d "$folder" ]]; then
      (cd "$folder" && pwd -P) || printf '%s\n' "$folder"
    else
      printf '%s\n' "$folder"
    fi
  done
)
# in_repository <path>: the path is one of those folders, or inside one.
in_repository() {
  local folder
  while IFS= read -r folder; do
    [[ -n "$folder" ]] || continue
    case "$1/" in "$folder"/*) return 0 ;; esac
  done <<< "$repo_folders"
  return 1
}
# The rules spell the path as written, so every folder on that path counts, not only where it ends: a symbolic link
# inside the repository that leads to a plugin outside it can be pointed at other scripts.
refuse_inside() {
  fail 6 "no rules offered: the plugin folder is inside this repository ($1). A session that edits files there could change the scripts and run them with no prompt. Approve each command instead."
}
plugin=$(cd "$here" && pwd -P)
! in_repository "$plugin" || refuse_inside "$plugin"
step=$here
while [[ "$step" != / && "$step" != . && -n "$step" ]]; do
  parent=$(cd "$(dirname "$step")" && pwd -P)
  entry="${parent%/}/$(basename "$step")"
  ! in_repository "$entry" || refuse_inside "$entry"
  step=$(dirname "$step")
done

# rule_for <path under the skills folder>: prints the rule for that spelling of a script.
rule_for() {
  local path="$skills/$1"
  case "$path" in
    *" "*) printf 'Bash(bash "%s" *)\n' "$path" ;;
    *) printf 'Bash(bash %s *)\n' "$path" ;;
  esac
}
# One line per spelling in a SKILL.md or reference.md (tests/test_permission_rules.sh compares them with the skills).
current=$(for spelling in $spellings; do rule_for "$spelling"; done)

# rules_in <file>: prints "<list>	<rule>" for each "Bash(...)" string that is an item of an array in a JSON file, one
# per line, without the JSON quotes and escapes. <list> is the key of the array (allow, deny, ask), or "-" when the
# array has no key. The file is read as tokens (strings and the characters []{}:,), so line breaks do not matter.
rules_in() {
  [[ -f "$1" ]] || return 0
  { tr -d '\r' < "$1" | grep -oE '"([^"\\]|\\.)*"|[][{}:]' || true; } | awk '
    {
      if ($0 == "[") { stack[++depth] = (before == ":" && before2 ~ /^"/) ? substr(before2, 2, length(before2) - 2) : "-" }
      else if ($0 == "{") { stack[++depth] = "{" }
      else if ($0 == "]" || $0 == "}") { if (depth > 0) depth-- }
      else if ($0 ~ /^"Bash\(.*\)"$/ && depth > 0 && stack[depth] != "{") {
        rule = substr($0, 2, length($0) - 2)
        gsub(/\\"/, "\"", rule); gsub(/\\\\/, "\\", rule)
        print stack[depth] "\t" rule
      }
      before2 = before; before = $0
    }'
}
# allowed_in <file>: the rules of its allow lists. blocked_in <file>: the rules of its deny and ask lists.
allowed_in() { rules_in "$1" | sed -n 's/^allow	//p'; }
blocked_in() { rules_in "$1" | sed -n -e 's/^deny	//p' -e 's/^ask	//p'; }
# names_our_script <rule>: a "Bash(bash ...)" rule that names a script this plugin has, or had, a rule for, under a
# folder with the plugin's name or after a wildcard. An exact path to a script of the same name elsewhere is not ours.
names_our_script() {
  local name
  case "$1" in
    "Bash(bash "*) ;;
    *) return 1 ;;
  esac
  for name in $our_scripts $named_only; do
    case "$1" in *"$plugin_name"*"$name"*) return 0 ;; esac
  done
  for name in $our_scripts; do
    case "$1" in *"*"*"$name"*) return 0 ;; esac
  done
  return 1
}
# stale_rules <file>: prints the rules in the file's allow lists to remove.
stale_rules() {
  local rule
  allowed_in "$1" | while IFS= read -r rule; do
    names_our_script "$rule" || continue
    grep -Fx -- "$rule" <<< "$current" > /dev/null || printf '%s\n' "$rule"
  done
}

main_file="$main/.claude/settings.local.json"
own_file="$root/.claude/settings.local.json"
in_main=$(allowed_in "$main_file")
blocked=$(blocked_in "$main_file")
stale=$(stale_rules "$main_file")
own_stale=""
if [[ "$root" != "$main" ]]; then own_stale=$(stale_rules "$own_file"); fi

# Windows (Git Bash, MSYS, Cygwin): the path and link checks of these scripts are not tested there, so no rule is
# offered and a current rule is listed for removal: each run then asks the user.
untested=""
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) untested=1 ;; esac

echo "file: $main_file"
missing=0
has_present=0
while IFS= read -r rule; do
  if [[ -n "$untested" ]]; then
    if grep -Fx -- "$rule" <<< "$in_main" > /dev/null; then echo "remove: $rule"; fi
    missing=3
  elif grep -Fx -- "$rule" <<< "$in_main" > /dev/null; then
    echo "present: $rule"
    has_present=1
  elif [[ -z "$stale$own_stale" ]]; then
    echo "add: $rule"
    missing=1
  else
    missing=2
  fi
  if grep -Fx -- "$rule" <<< "$blocked" > /dev/null; then
    echo "note: this rule is also in a deny or ask list of the file, and that list wins: $rule"
  fi
done <<< "$current"
[[ -z "$stale" ]] || printf '%s\n' "$stale" | sed 's/^/remove: /'
[[ -z "$untested" ]] || echo "note: no allow rule is offered on Windows: the scripts' path and link checks are not tested there, so each run must ask the user. Remove any \"remove\" rule above."
if [[ -n "$own_stale" ]]; then
  echo "file: $own_file"
  printf '%s\n' "$own_stale" | sed 's/^/remove: /'
fi

if [[ -n "$stale$own_stale" ]]; then
  echo "note: the \"remove\" rules must go from permissions.allow before anything else: they are not among the rules offered now. A rule for another plugin version still approves that version's scripts, which stay on disk after an update, with no prompt; a rule with a wildcard before the script path allows any command. Show them to the user, say why, and delete them."
  [[ "$missing" -ne 2 ]] || echo "note: no \"add\" rule is offered while a \"remove\" rule is there. Run this script again after the old rules are gone."
  echo "note: this script reads only the two files named above. Tell the user to remove the same rules from any other settings file they copied them to (another worktree's .claude/settings.local.json, .claude/settings.json, ~/.claude/settings.json)."
fi
[[ "$missing" -ne 1 ]] || echo "note: show the user the \"add\" rules; only on a yes, put them in permissions.allow of the first file."
[[ "$has_present" -eq 0 ]] || echo "note: a \"present\" rule is in an allow list of the file."
