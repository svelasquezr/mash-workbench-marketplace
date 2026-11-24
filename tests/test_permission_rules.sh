# shellcheck shell=bash
# permission-rules.sh (mash-workbench, skills/scout): the Claude Code allow rules that setup offers for the recording
# script. Each rule names one exact script path and has one wildcard, at the end: a wildcard before the script path
# allows any command.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
plugin_source="$PWD/plugins/mash-workbench"
fixture=$(mktemp -d "$HOME/.permission-rules-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
fixture=$(cd "$fixture" && pwd -P)
temporary_directory="$fixture"
isolate_git_config
export LC_ALL=C  # one sort order everywhere

# An installed copy of the plugin, outside every repository the tests use.
installed="$fixture/cache/mash-workbench/0.0.1"
mkdir -p "$installed"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$installed/"
rules_script="$installed/skills/scout/permission-rules.sh"

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

# 1. The rule: for the one spelling that a skill writes, the path exact, one wildcard at the end.
repo=$(new_repo plain)
run_capturing bash "$rules_script" "$repo"
assert_eq "$captured_exit_code" 0
expected="Bash(bash $installed/skills/scout/backlog-add.sh *)"
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

# 2. Every spelling the skills write for the script has a rule, and every rule is a spelling a skill writes.
from_docs=""
for document in "$plugin_source"/skills/*/SKILL.md "$plugin_source"/skills/*/reference.md; do
  [[ -f "$document" ]] || continue
  skill=$(basename "$(dirname "$document")")
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    from_docs+="Bash(bash $installed/skills/$skill/${match#"<this skill's base directory>/"} *)"$'\n'
  done <<< "$(grep -o "<this skill's base directory>/[^][:space:]\`'\"<>()]*backlog-add\.sh" "$document" || true)"
done
assert_eq "$(printf '%s' "$from_docs" | sort -u)" "$expected"

# 3. The same answer however the script is called: through "..", and by a relative path.
run_capturing bash "$installed/skills/forge/../scout/permission-rules.sh" "$repo"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"
# shellcheck disable=SC2016  # the inner bash expands $1 and $2
run_capturing bash -c 'cd "$1" && bash ./permission-rules.sh "$2"' _ "$installed/skills/scout" "$repo"
assert_eq "$(lines_with add "$captured_output" | sort)" "$expected"

# 4. A settings file with old rules: the current rule is present, the rest are to add, and every other rule that
#    names one of the plugin's scripts is to remove (a wildcard rule, and another version's rule). Rules for other
#    commands are not named.
mkdir -p "$repo/.claude"
current="$expected"
other_version="Bash(bash $fixture/cache/mash-workbench/0.0.0/skills/scout/backlog-add.sh *)"
cat > "$repo/.claude/settings.local.json" <<EOF
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(bash */mash-workbench/*scout/backlog-add.sh*)",
      "Bash(bash */mash-workbench/*scripts/mash-settings.sh*)",
      "Bash(bash $fixture/tools/backlog-add.sh *)",
      "Bash(cat *backlog-add.sh*)",
      "$other_version",
      "$current"
    ]
  }
}
EOF
run_capturing bash "$rules_script" "$repo"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with present "$captured_output")" "$current"
# Removing the old rules is not optional: while one is there, no new rule is offered.
assert_eq "$(lines_with add "$captured_output")" ""
assert_contains "$captured_output" "must go"
assert_contains "$captured_output" "still approves that version's scripts"
assert_contains "$captured_output" "any other settings file"
assert_eq "$(lines_with remove "$captured_output" | sort)" "Bash(bash */mash-workbench/*scout/backlog-add.sh*)
$other_version"
assert_not_contains "$captured_output" "git status"
assert_not_contains "$captured_output" "mash-settings.sh"
assert_not_contains "$captured_output" "tools/backlog-add.sh"
assert_not_contains "$captured_output" "Bash(cat"
assert_contains "$captured_output" "allows any command"
# 4b. With the old rules gone, the missing rule is offered.
cat > "$repo/.claude/clean.json" <<EOF
{"permissions": {"allow": ["Bash(git status *)"], "deny": ["$other_version"]}}
EOF
cp "$repo/.claude/settings.local.json" "$repo/.claude/with-old.json"
cp "$repo/.claude/clean.json" "$repo/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo"
assert_eq "$(lines_with present "$captured_output")" ""
assert_eq "$(lines_with add "$captured_output")" "$expected"
assert_eq "$(lines_with remove "$captured_output")" ""
cp "$repo/.claude/with-old.json" "$repo/.claude/settings.local.json"
rm "$repo/.claude/clean.json" "$repo/.claude/with-old.json"

# 5. The same file on one line (no line breaks between the rules).
tr -d '\n' < "$repo/.claude/settings.local.json" > "$repo/.claude/one-line"
mv "$repo/.claude/one-line" "$repo/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo"
assert_eq "$(lines_with present "$captured_output")" "$current"
assert_eq "$(lines_with remove "$captured_output" | wc -l | tr -d ' ')" 2

# 6. From a linked worktree: the file is the main worktree's; old rules in the worktree's own file are named too.
git -C "$repo" worktree add --quiet "$repo/.claude/worktrees/w1" -b w1
mkdir -p "$repo/.claude/worktrees/w1/.claude"
printf '{"permissions":{"allow":["Bash(bash *backlog-add.sh *)"]}}\n' > "$repo/.claude/worktrees/w1/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo/.claude/worktrees/w1"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with file "$captured_output")" "$repo/.claude/settings.local.json
$repo/.claude/worktrees/w1/.claude/settings.local.json"
assert_eq "$(lines_with present "$captured_output")" "$current"
assert_contains "$captured_output" "remove: Bash(bash *backlog-add.sh *)"
# An old rule only in the linked worktree's own file also holds the new rule back.
printf '{"permissions":{"allow":[]}}\n' > "$repo/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo/.claude/worktrees/w1"
assert_eq "$(lines_with add "$captured_output")" ""
assert_contains "$captured_output" "remove: Bash(bash *backlog-add.sh *)"
assert_contains "$captured_output" "Run this script again"
rm "$repo/.claude/worktrees/w1/.claude/settings.local.json"
run_capturing bash "$rules_script" "$repo/.claude/worktrees/w1"
assert_eq "$(lines_with add "$captured_output")" "$expected"

# 7. A plugin path with a space: the rule spells the path in double quotes, and a rule stored with JSON escapes is found.
spaced="$fixture/sp ace/mash-workbench"
mkdir -p "$spaced"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$spaced/"
clean=$(new_repo spaced)
run_capturing bash "$spaced/skills/scout/permission-rules.sh" "$clean"
assert_eq "$captured_exit_code" 0
assert_contains "$captured_output" "add: Bash(bash \"$spaced/skills/scout/backlog-add.sh\" *)"
mkdir -p "$clean/.claude"
printf '{"permissions":{"allow":["Bash(bash \\"%s/skills/scout/backlog-add.sh\\" *)"]}}\n' "$spaced" > "$clean/.claude/settings.local.json"
run_capturing bash "$spaced/skills/scout/permission-rules.sh" "$clean"
assert_eq "$(lines_with present "$captured_output")" "Bash(bash \"$spaced/skills/scout/backlog-add.sh\" *)"

# 8. A plugin path that a rule cannot spell (a wildcard, a "$", a quote, ...): no rule is printed, exit 6.
# shellcheck disable=SC2016  # the "$" and the backtick are part of a folder name
for name in 'st*ar' 'dol$lar' 'par(en' 'par)en' 'back\slash' 'dou"ble' "sin'gle" 'amp&er' 'semi;colon' 'back`tick' 'bra{ce' 'ha#sh' 'ba!ng' 'pi|pe' 'que?stion' 'brack[et' 'les<s' $'new\nline' $'ta\tb'; do
  odd="$fixture/$name/mash-workbench"
  mkdir -p "$odd"
  cp -R "$plugin_source/skills" "$plugin_source/scripts" "$odd/"
  run_capturing bash "$odd/skills/scout/permission-rules.sh" "$clean"
  assert_eq "$captured_exit_code" 6
  assert_not_contains "$captured_output" "Bash("
done

# 9. A plugin folder inside the repository: a session that edits files there could change the scripts, so no rule
#    is printed, exit 6. The same from a linked worktree of that repository.
inside=$(new_repo inside)
mkdir -p "$inside/plugins/mash-workbench"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$inside/plugins/mash-workbench/"
run_capturing bash "$inside/plugins/mash-workbench/skills/scout/permission-rules.sh" "$inside"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("
assert_contains "$captured_output" "inside"
git -C "$inside" worktree add --quiet "$inside/.claude/worktrees/w1" -b w1
run_capturing bash "$inside/plugins/mash-workbench/skills/scout/permission-rules.sh" "$inside/.claude/worktrees/w1"
assert_eq "$captured_exit_code" 6

# 9b. A symbolic link inside the repository that leads to a plugin outside it: the rules would name the link, and a
#     session could point it at other scripts. No rule, exit 6. Also when the repository is reached through a link.
linked=$(new_repo linked)
mkdir -p "$linked/vendor"
if ln -s "$installed" "$linked/vendor/rr" 2>/dev/null && [[ -L "$linked/vendor/rr" ]]; then
  run_capturing bash "$linked/vendor/rr/skills/scout/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 6
  assert_not_contains "$captured_output" "Bash("
  ln -s "$linked" "$fixture/alias"
  run_capturing bash "$fixture/alias/vendor/rr/skills/scout/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 6
  # A link outside every worktree is fine: the rules spell the path as it was written.
  ln -s "$installed" "$fixture/current"
  run_capturing bash "$fixture/current/skills/scout/permission-rules.sh" "$linked"
  assert_eq "$captured_exit_code" 0
  assert_contains "$captured_output" "add: Bash(bash $fixture/current/skills/scout/backlog-add.sh *)"
fi

# 9c. A plugin folder inside a linked worktree that lives outside the main worktree: no rule, exit 6.
git -C "$linked" worktree add --quiet "$fixture/sibling" -b sibling
mkdir -p "$fixture/sibling/plugins/mash-workbench"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$fixture/sibling/plugins/mash-workbench/"
run_capturing bash "$fixture/sibling/plugins/mash-workbench/skills/scout/permission-rules.sh" "$linked"
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
mkdir -p "$fixture/gone-worktree/mash-workbench"
cp -R "$plugin_source/skills" "$plugin_source/scripts" "$fixture/gone-worktree/mash-workbench/"
run_capturing bash "$fixture/gone-worktree/mash-workbench/skills/scout/permission-rules.sh" "$gone"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("

# 9d. The lists are told apart: a current rule in a deny or ask list is not "present" (a note says the list wins), and
#     an old rule in a deny list is not a rule to remove, so it holds nothing back. Other arrays do not count.
denied=$(new_repo denied)
mkdir -p "$denied/.claude"
first_rule=$(bash "$rules_script" "$denied" | sed -n 's/^add: //p' | head -n 1)
cat > "$denied/.claude/settings.local.json" <<EOF
{
  "permissions": {
    "deny": ["$first_rule", "Bash(bash */mash-workbench/*scout/backlog-add.sh*)"],
    "ask": [ "Bash(bash */mash-workbench/*scout/backlog-add.sh*)" ],
    "allow": []
  },
  "notes": { "list": ["Bash(bash */mash-workbench/*scout/backlog-add.sh*)"], "allow": "Bash(bash *backlog-add.sh *)" },
  "nested": [ { "allow": "Bash(bash *backlog-add.sh *)" } ]
}
EOF
run_capturing bash "$rules_script" "$denied"
assert_eq "$captured_exit_code" 0
assert_eq "$(lines_with present "$captured_output")" ""
assert_eq "$(lines_with remove "$captured_output")" ""
assert_eq "$(lines_with add "$captured_output")" "$expected"
assert_contains "$captured_output" "note: this rule is also in a deny or ask list of the file, and that list wins: $first_rule"

# 9f. An old version's rule is named to remove; an exact rule of another plugin (review-routing) is left alone.
mash=$(new_repo mash)
mkdir -p "$mash/.claude"
printf '{"permissions":{"allow":["Bash(bash %s/cache/mash-workbench/0.0.0/skills/scout/backlog-add.sh *)","Bash(bash /x/review-routing/1/skills/add-reviewer/escape-add.sh *)"]}}\n' "$fixture" > "$mash/.claude/settings.local.json"
run_capturing bash "$rules_script" "$mash"
assert_eq "$(lines_with remove "$captured_output")" "Bash(bash $fixture/cache/mash-workbench/0.0.0/skills/scout/backlog-add.sh *)"
assert_eq "$(lines_with add "$captured_output")" ""
assert_not_contains "$captured_output" "review-routing"
# A copy in any other folder says so and offers nothing.
mkdir -p "$fixture/odd-place/skills/other"; cp "$rules_script" "$fixture/odd-place/skills/other/"
run_capturing bash "$fixture/odd-place/skills/other/permission-rules.sh" "$mash"
assert_eq "$captured_exit_code" 6
assert_not_contains "$captured_output" "Bash("

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
# mash-review's migrate skill names an old rule as one to remove; that is not an offer. Only folders that exist are
# searched: a missing one would make grep fail and hide every match.
shipped_folders=()
for folder in plugins/*/skills plugins/*/scripts; do [[ -d "$folder" ]] && shipped_folders+=("$folder"); done
wildcard_offers=$(grep -rn 'Bash(bash \*' "${shipped_folders[@]}" | grep -v 'permission-rules.sh' | grep -v 'mash-review/skills/migrate/' || true)
if [[ -n "$wildcard_offers" ]]; then
  echo "$wildcard_offers"
  echo "  a shipped file still shows an allow rule that starts with a wildcard"
  exit 1
fi
