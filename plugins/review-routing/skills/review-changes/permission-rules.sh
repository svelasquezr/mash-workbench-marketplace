#!/usr/bin/env bash
# Print the Claude Code allow rules that let a session with no user (claude -p in a linked worktree) record escapes
# and log reviews without a prompt, and name the old rules to remove. It only prints: the user decides, and the
# session edits the settings file with its edit tool, so Claude Code asks the user to approve that write.
#
# Usage: permission-rules.sh <repo-root>
#
# Output, one item per line:
#   file: <path>      a .claude/settings.local.json: first the main worktree's (where the rules go), then, from a
#                     linked worktree that has its own file with rules to remove, that file. The lines below a
#                     "file:" line are about that file.
#   present: <rule>   a current rule that the file already holds
#   add: <rule>       a current rule that the file does not hold
#   remove: <rule>    a "Bash(bash ...)" rule in the file that is not a current rule and names one of this plugin's
#                     scripts, either under a review-routing folder (a rule for another plugin version) or after a
#                     wildcard. The rules of review-routing 0.4.0 to 0.5.0 started with a wildcard
#                     ("Bash(bash */review-routing/*add-reviewer/escape-add.sh*)"), and "*" matches any text, spaces
#                     too, so they allowed any command that mentions the script's name. A rule for a script of the
#                     same name elsewhere, with an exact path, is left alone.
#   note: <text>      what to do with the lines above
#
# The rules. Claude Code compares a rule with the command text letter for letter, and a rule is safe only when
# nothing but the arguments can vary. So each rule is "Bash(bash <script path> *)": the exact path of this installed
# copy, and one wildcard, at the end. There is one rule for each spelling a skill writes ("<skills>/record-escape/../
# add-reviewer/escape-add.sh" and "<skills>/add-reviewer/escape-add.sh" are two texts), for the two scripts a session
# with no user needs: escape-add.sh and review-log.sh. The steps that need a user's answer first (escape-migrate.sh,
# mash-settings.sh set) get no rule. A path with a space is spelled in double quotes, as a session must write it.
# The path holds the plugin's version folder, so the rules stop matching after a plugin update, on purpose: run
# this script again, then add the new rules and remove the old ones.
# What a rule still allows: any arguments to that one script. escape-add.sh copies the --body-file it is given into
# the escapes folder, and review-log.sh add writes a line to reviews.log.
#
# Reads: the two settings.local.json files named above, only their "Bash(...)" strings. It does not tell the allow,
# deny and ask lists apart: a "present" rule may sit in a deny list, and a "remove" rule may be a deny rule the user
# wrote (the note says so). Writes nothing. No network.
# Exit codes: 0 success; 2 usage error, or <repo-root> is not in a git repository; 5 bare repository, or the main
# worktree cannot be found; 6 no rules offered: the plugin folder, or a symbolic link on the path to it, is inside a
# worktree of the repository (a session that edits files there could change the scripts, or point the link at other
# scripts, and then run them with no prompt), or the path holds a character that a rule cannot spell safely (anything
# but letters, digits, space and _ . / : @ % + = , ~ -).
# Plain bash 3.2 (macOS) and Git Bash: no associative arrays, no ${var,,}, no mapfile.
set -euo pipefail

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
[[ "$here" == */skills/review-changes ]] || fail 6 "not in a plugin's skills/review-changes folder: $here"
skills=${here%/review-changes}

safe_path='^[A-Za-z0-9 _./:@%+=,~-]+$'
[[ "$skills" =~ $safe_path ]] || fail 6 "no rules offered: the plugin path holds a character that a rule cannot spell safely: $skills"

root=$(cd "$1" && pwd -P)
main=$(bash "$here/../../scripts/mash-settings.sh" main-worktree "$root") || exit $?
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
current=$(
  rule_for add-reviewer/escape-add.sh
  rule_for review-changes/../add-reviewer/escape-add.sh
  rule_for record-escape/../add-reviewer/escape-add.sh
  rule_for review-changes/review-log.sh
  rule_for record-escape/../review-changes/review-log.sh
)

# rules_in <file>: prints each "Bash(...)" string in a JSON file, one per line, without the JSON quotes and escapes.
rules_in() {
  [[ -f "$1" ]] || return 0
  { tr -d '\r' < "$1" | grep -oE '"Bash\(([^"\\]|\\.)*\)"' || true; } \
    | sed -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}
# names_our_script <rule>: a "Bash(bash ...)" rule that names a script this plugin had, or has, a rule for, under a
# review-routing folder or after a wildcard. An exact path to a script of the same name elsewhere is not ours.
names_our_script() {
  case "$1" in
    "Bash(bash "*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *review-routing*escape-add.sh* | *review-routing*escape-migrate.sh* | *review-routing*review-log.sh*) return 0 ;;
    *review-routing*mash-settings.sh*) return 0 ;;
    *"*"*escape-add.sh* | *"*"*escape-migrate.sh* | *"*"*review-log.sh*) return 0 ;;
  esac
  return 1
}
# stale_rules <file>: prints the rules in the file to remove.
stale_rules() {
  local rule
  rules_in "$1" | while IFS= read -r rule; do
    names_our_script "$rule" || continue
    grep -Fx -- "$rule" <<< "$current" > /dev/null || printf '%s\n' "$rule"
  done
}

main_file="$main/.claude/settings.local.json"
in_main=$(rules_in "$main_file")
echo "file: $main_file"
missing=0
while IFS= read -r rule; do
  if grep -Fx -- "$rule" <<< "$in_main" > /dev/null; then
    echo "present: $rule"
  else
    echo "add: $rule"
    missing=1
  fi
done <<< "$current"
stale=$(stale_rules "$main_file")
[[ -z "$stale" ]] || printf '%s\n' "$stale" | sed 's/^/remove: /'
found_stale=$stale

own_file="$root/.claude/settings.local.json"
if [[ "$root" != "$main" ]]; then
  stale=$(stale_rules "$own_file")
  if [[ -n "$stale" ]]; then
    echo "file: $own_file"
    printf '%s\n' "$stale" | sed 's/^/remove: /'
    found_stale+=$stale
  fi
fi

[[ "$missing" -eq 0 ]] || echo "note: show the user the \"add\" rules; only on a yes, put them in permissions.allow of the first file."
[[ -z "$found_stale" ]] || echo "note: tell the user to remove the \"remove\" rules from permissions.allow: they are not among the rules offered now (another plugin version, or a script that gets no rule any more), or they have a wildcard before the script path, and such a rule allows any command. A rule in a deny or ask list can stay."
[[ "$missing" -eq 1 ]] || echo "note: a \"present\" rule works only in permissions.allow; this script does not tell the allow, deny and ask lists apart."
