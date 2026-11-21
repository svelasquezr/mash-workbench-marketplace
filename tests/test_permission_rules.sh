# shellcheck shell=bash
# permission-rules.sh: the Claude Code allow rules that setup offers for the recording scripts. Each rule names one
# exact script path and has one wildcard, at the end: a wildcard before the script path allows any command.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
plugin_source="$PWD/plugins/review-routing"
fixture=$(mktemp -d "$HOME/.permission-rules-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
fixture=$(cd "$fixture" && pwd -P)
temporary_directory="$fixture"
isolate_git_config
export LC_ALL=C  # one sort order everywhere

# An installed copy of the plugin, outside every repository the tests use.
installed="$fixture/cache/review-routing/0.0.1"
mkdir -p "$installed"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$installed/"
rules_script="$installed/skills/review-changes/permission-rules.sh"

new_repo() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  mkdir -p "$folder/.git/info"
  echo ".claude/worktrees/" >> "$folder/.git/info/exclude"
  echo base > "$folder/base"
  git -C "$folder" add base
  git -C "$folder" commit --quiet -m "chore: base"
  (cd "$folder" && pwd -P)
}
# lines_with <prefix> <text>: the lines of <text> that start with "<prefix>: ", without the prefix.
lines_with() { printf '%s\n' "$2" | { grep "^$1: " || true; } | sed "s/^$1: //"; }

# 1. The rules: one per spelling that a skill writes, the path exact, one wildcard at the end.
repo=$(new_repo plain)
run_capturing bash "$rules_script" "$repo"
assert_eq "$captured_exit_code" 0
expected="Bash(bash $installed/skills/add-reviewer/escape-add.sh *)
Bash(bash $installed/skills/record-escape/../add-reviewer/escape-add.sh *)
Bash(bash $installed/skills/record-escape/../review-changes/review-log.sh *)
Bash(bash $installed/skills/review-changes/../add-reviewer/escape-add.sh *)
Bash(bash $installed/skills/review-changes/review-log.sh *)"
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"
assert_eq "$(lines_with file "$captured_output")" "$repo/.claude/settings.local.json"
assert_eq "$(lines_with present "$captured_output")" ""
assert_eq "$(lines_with remove "$captured_output")" ""
# No wildcard except the last two characters before ")".
while IFS= read -r rule; do
  body=${rule%" *)"}
  [[ "$body" != "$rule" ]] || { echo "  rule does not end with ' *)': $rule"; exit 1; }
  assert_not_contains "$body" "*"
done <<< "$(lines_with add "$captured_output")"

# 2. Every spelling the skills write for the two scripts has a rule, and every rule is a spelling a skill writes.
from_docs=""
for document in "$plugin_source"/skills/*/SKILL.md "$plugin_source"/skills/*/reference.md; do
  skill=$(basename "$(dirname "$document")")
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    from_docs+="Bash(bash $installed/skills/$skill/${match#"<this skill's base directory>/"} *)"$'\n'
  done <<< "$(grep -o "<this skill's base directory>/[^][:space:]\`'\"<>()]*\(escape-add\|review-log\)\.sh" "$document" || true)"
done
assert_eq "$(printf '%s' "$from_docs" | sort -u)" "$expected"

# 3. The same answer however the script is called: through "..", and by a relative path.
run_capturing bash "$installed/skills/record-escape/../review-changes/permission-rules.sh" "$repo"
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"
# shellcheck disable=SC2016  # the inner bash expands $1 and $2
run_capturing bash -c 'cd "$1" && bash ./permission-rules.sh "$2"' _ "$installed/skills/review-changes" "$repo"
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"

# 4. A settings file with old rules: the current rule is present, the rest are to add, and every other rule that
#    names one of the plugin's scripts is to remove (the 0.4.0 to 0.5.0 wildcard rules, and another version's rules).
#    Rules for other commands are not named.
mkdir -p "$repo/.claude"
current="Bash(bash $installed/skills/review-changes/review-log.sh *)"
other_version="Bash(bash $fixture/cache/review-routing/0.0.0/skills/review-changes/review-log.sh *)"
cat > "$repo/.claude/settings.local.json" <<EOF
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(bash */review-routing/*add-reviewer/escape-add.sh*)",
      "Bash(bash */review-routing/*add-reviewer/escape-migrate.sh*)",
      "Bash(bash */review-routing/*review-changes/review-log.sh*)",
      "Bash(bash */review-routing/*scripts/mash-settings.sh*)",
      "Bash(bash */mash-workbench/*scripts/mash-settings.sh*)",
      "Bash(bash $fixture/tools/review-log.sh *)",
      "Bash(cat *escape-add.sh*)",
      "$other_version",
      "$current"
    ]
  }
}
EOF
run_capturing bash "$rules_script" "$repo"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with present "$captured_output")" "$current"
assert_eq "$(lines_with add "$captured_output" | wc -l | tr -d ' ')" 4
assert_eq "$(lines_with remove "$captured_output" | sort)" "Bash(bash */review-routing/*add-reviewer/escape-add.sh*)
Bash(bash */review-routing/*add-reviewer/escape-migrate.sh*)
Bash(bash */review-routing/*review-changes/review-log.sh*)
Bash(bash */review-routing/*scripts/mash-settings.sh*)
$other_version"
assert_not_contains "$captured_output" "git status"
assert_not_contains "$captured_output" "mash-workbench/"
assert_not_contains "$captured_output" "tools/review-log.sh"
assert_not_contains "$captured_output" "Bash(cat"
assert_contains "$captured_output" "allows any command"

# 5. The same file on one line (no line breaks between the rules).
tr -d '\n' < "$repo/.claude/settings.local.json" > "$repo/.claude/one-line"
mv "$repo/.claude/one-line" "$repo/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo"
assert_eq "$(lines_with present "$captured_output")" "$current"
assert_eq "$(lines_with remove "$captured_output" | wc -l | tr -d ' ')" 5

# 6. From a linked worktree: the file is the main worktree's; old rules in the worktree's own file are named too.
git -C "$repo" worktree add --quiet "$repo/.claude/worktrees/w1" -b w1
mkdir -p "$repo/.claude/worktrees/w1/.claude"
printf '{"permissions":{"allow":["Bash(bash *escape-add.sh *)"]}}\n' > "$repo/.claude/worktrees/w1/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo/.claude/worktrees/w1"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with file "$captured_output")" "$repo/.claude/settings.local.json
$repo/.claude/worktrees/w1/.claude/settings.local.json"
assert_eq "$(lines_with present "$captured_output")" "$current"
assert_contains "$captured_output" "remove: Bash(bash *escape-add.sh *)"

# 7. A plugin path with a space: the rule spells the path in double quotes, and a rule stored with JSON escapes is found.
spaced="$fixture/sp ace/review-routing"
mkdir -p "$spaced"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$spaced/"
clean=$(new_repo spaced)
run_capturing bash "$spaced/skills/review-changes/permission-rules.sh" "$clean"
assert_eq "$captured_exit_code" 0
assert_contains "$captured_output" "add: Bash(bash \"$spaced/skills/review-changes/review-log.sh\" *)"
mkdir -p "$clean/.claude"
printf '{"permissions":{"allow":["Bash(bash \\"%s/skills/review-changes/review-log.sh\\" *)"]}}\n' "$spaced" > "$clean/.claude/settings.local.json"
run_capturing bash "$spaced/skills/review-changes/permission-rules.sh" "$clean"
assert_eq "$(lines_with present "$captured_output")" "Bash(bash \"$spaced/skills/review-changes/review-log.sh\" *)"

# 8. A plugin path that a rule cannot spell (a wildcard, a "$", a quote, ...): no rule is printed, exit 6.
# shellcheck disable=SC2016  # the "$" and the backtick are part of a folder name
for name in 'st*ar' 'dol$lar' 'par(en' 'par)en' 'back\slash' 'dou"ble' "sin'gle" 'amp&er' 'semi;colon' 'back`tick' 'bra{ce' 'ha#sh' 'ba!ng' 'pi|pe' 'que?stion' 'brack[et' 'les<s' $'new\nline' $'ta\tb'; do
  odd="$fixture/$name/review-routing"
  mkdir -p "$odd"
  cp -R "$plugin_source/skills" "$plugin_source/scripts" "$odd/"
  run_capturing bash "$odd/skills/review-changes/permission-rules.sh" "$clean"
  assert_eq "$captured_exit_code" 6
  assert_not_contains "$captured_output" "Bash("
done

# 9. A plugin folder inside the repository: a session that edits files there could change the scripts, so no rule
#    is printed, exit 6. The same from a linked worktree of that repository.
inside=$(new_repo inside)
mkdir -p "$inside/plugins/review-routing"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$inside/plugins/review-routing/"
run_capturing bash "$inside/plugins/review-routing/skills/review-changes/permission-rules.sh" "$inside"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("
assert_contains "$captured_output" "inside"
git -C "$inside" worktree add --quiet "$inside/.claude/worktrees/w1" -b w1
run_capturing bash "$inside/plugins/review-routing/skills/review-changes/permission-rules.sh" "$inside/.claude/worktrees/w1"
assert_eq "$captured_exit_code" 6

# 9b. A symbolic link inside the repository that leads to a plugin outside it: the rules would name the link, and a
#     session could point it at other scripts. No rule, exit 6. Also when the repository is reached through a link.
linked=$(new_repo linked)
mkdir -p "$linked/vendor"
if ln -s "$installed" "$linked/vendor/rr" 2>/dev/null && [[ -L "$linked/vendor/rr" ]]; then
  run_capturing bash "$linked/vendor/rr/skills/review-changes/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 6
  assert_not_contains "$captured_output" "Bash("
  ln -s "$linked" "$fixture/alias"
  run_capturing bash "$fixture/alias/vendor/rr/skills/review-changes/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 6
  # A link outside every worktree is fine: the rules spell the path as it was written.
  ln -s "$installed" "$fixture/current"
  run_capturing bash "$fixture/current/skills/review-changes/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 0
  assert_contains "$captured_output" "add: Bash(bash $fixture/current/skills/review-changes/review-log.sh *)"
fi

# 9c. A plugin folder inside a linked worktree that lives outside the main worktree: no rule, exit 6.
git -C "$linked" worktree add --quiet "$fixture/sibling" -b sibling
mkdir -p "$fixture/sibling/plugins/review-routing"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$fixture/sibling/plugins/review-routing/"
run_capturing bash "$fixture/sibling/plugins/review-routing/skills/review-changes/permission-rules.sh" "$linked"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("

# 9e. A listed worktree whose folder was deleted by hand (not pruned), listed last: the script still answers, and a
#     plugin folder put back at that path is still refused.
gone=$(new_repo gone)
git -C "$gone" worktree add --quiet "$fixture/gone-worktree" -b gone-worktree
rm -rf "$fixture/gone-worktree"
assert_eq "$(git -C "$gone" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n 1)" "$fixture/gone-worktree"
run_capturing bash "$rules_script" "$gone"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"
mkdir -p "$fixture/gone-worktree/review-routing"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$fixture/gone-worktree/review-routing/"
run_capturing bash "$fixture/gone-worktree/review-routing/skills/review-changes/permission-rules.sh" "$gone"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("

# 9d. The notes say that the lists are not told apart: a current rule in a deny list still prints "present".
denied=$(new_repo denied)
mkdir -p "$denied/.claude"
{
  printf '{"permissions":{"deny":['
  bash "$rules_script" "$denied" | sed -n 's/^add: \(.*\)$/"\1"/p' | paste -sd, -
  printf ']}}\n'
} > "$denied/.claude/settings.local.json"
run_capturing bash "$rules_script" "$denied"
assert_eq "$(lines_with present "$captured_output" | wc -l | tr -d ' ')" 5
assert_contains "$captured_output" "does not tell the allow, deny and ask lists apart"

# 10. Usage errors, and a folder that is not in a git repository.
run_capturing bash "$rules_script"
assert_eq "$captured_exit_code" 2
run_capturing bash "$rules_script" "$fixture/no-such-folder"
assert_eq "$captured_exit_code" 2
mkdir -p "$fixture/not-a-repo"
run_capturing bash "$rules_script" "$fixture/not-a-repo"
assert_eq "$captured_exit_code" 2
assert_not_contains "$captured_output" "Bash("

# 11. The script writes nothing: the repository and the settings file are unchanged.
before=$(cd "$repo" && find . -type f -not -path './.git/*' -exec cksum {} + | sort)
bash "$rules_script" "$repo" > /dev/null
assert_eq "$(cd "$repo" && find . -type f -not -path './.git/*' -exec cksum {} + | sort)" "$before"

# 12. No shipped text offers a rule with a wildcard before the script path any more.
if grep -rn 'Bash(bash \*' plugins/*/skills plugins/*/scripts plugins/*/hooks | grep -v 'permission-rules.sh'; then
  echo "  a shipped file still shows an allow rule that starts with a wildcard"
  exit 1
fi
