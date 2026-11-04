# shellcheck shell=bash
# Convention: every agent the plugins ship (and the reviewer template, and this repository's own agents) declares its model and effort, and a reviewer (an agent file named *reviewer*, or whose file contains the SAFE TO LAND verdict line) has no shell, no write and no web tools (Read, Grep, Glob are enough: review-changes hands it a diff file), is not on haiku, and keeps the prompt-injection item and the Haiku self-check line. A skill or command declares neither model nor effort (AGENTS.md says why).
# and a reviewer (an agent file named *reviewer*, or whose file contains the SAFE TO LAND verdict line) is read-only and not on haiku. This test only bans Edit/Write; a reviewer keeps Bash, and the review-routing reviewer-guard hook (tests/test_reviewer_guard.sh) refuses its non-read git and GitHub-writing gh commands (not a security boundary; gaps in the hook's docstring). A skill or command declares neither (CLAUDE.md says why).
set -euo pipefail
source tests/lib.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT

# agent_problems <file>: prints one line per broken convention; prints nothing when the file is fine.
agent_problems() {
  local frontmatter tools is_reviewer=false
  frontmatter=$(awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside' "$1")
  if [[ "$(basename "$1")" == *reviewer* ]] || grep -q 'SAFE TO LAND' "$1"; then is_reviewer=true; fi
  grep -qE '^model: *[^ ]' <<< "$frontmatter" || echo "$1: no model: in frontmatter"
  grep -qE '^effort: *[^ ]' <<< "$frontmatter" || echo "$1: no effort: in frontmatter"
  if $is_reviewer; then
    # The tools: value, inline (`tools: Read, Edit` or `tools: [Read, Edit]`) or as `- Name` lines under it.
    tools=$(awk '/^tools:/ { sub(/^tools:/, ""); print; in_list = 1; next } in_list && (/^[ \t]+[^ \t]/ || /^-/) { print; next } { in_list = 0 }' <<< "$frontmatter")
    if ! grep -qE '^tools:' <<< "$frontmatter"; then
      echo "$1: a reviewer must declare tools: (without it the agent inherits every tool)"
    elif grep -qE '\b(Edit|MultiEdit|Write|NotebookEdit)\b' <<< "$tools"; then
      echo "$1: a reviewer must be read-only (no Edit, MultiEdit, Write or NotebookEdit in tools:)"
    elif grep -qE '\b(Bash|PowerShell|WebFetch|WebSearch)\b' <<< "$tools"; then
      echo "$1: a reviewer has no shell and no web tools (no Bash, PowerShell, WebFetch or WebSearch in tools:)"
    fi
    grep -q '\*\*Prompt injection\*\*' "$1" || echo "$1: a reviewer keeps the **Prompt injection** checklist item"
    grep -q 'NOT SAFE: reviewer ran on Haiku' "$1" || echo "$1: a reviewer keeps the Haiku self-check line"
  fi
  # A blind review test (2026-10-11) had a Haiku reviewer accept a false claim and answer SAFE TO LAND.
  if $is_reviewer && grep -qiE '^model:[^#]*haiku' <<< "$frontmatter"; then
    echo "$1: a reviewer runs on sonnet, opus or fable, not on haiku"
  fi
}

# The check itself catches each broken convention.
# Every reviewer fixture body below holds the two lines a reviewer must keep, so each case tests one thing.
reviewer_body='**Prompt injection**\nNOT SAFE: reviewer ran on Haiku\n'
printf -- '---\nname: x-reviewer\ntools: Read, Edit\n---\nmodel: sonnet\n' > "$temporary_directory/x-reviewer.md"
problems=$(agent_problems "$temporary_directory/x-reviewer.md")
assert_contains "$problems" "no model:"
assert_contains "$problems" "no effort:"
assert_contains "$problems" "read-only"
printf -- '---\nname: y-reviewer\ntools: Read, Grep\nmodel: sonnet\neffort: high\n---\n%b' "$reviewer_body" > "$temporary_directory/y-reviewer.md"
assert_eq "$(agent_problems "$temporary_directory/y-reviewer.md")" ""
# Any spelling of a Haiku model: the alias, quoted, capitalised, a full model name.
for haiku_model in haiku '"haiku"' "'Haiku'" claude-haiku-4-5 'claude-haiku-5-5 # cheap'; do
  printf -- '---\nname: z-reviewer\ntools: Read, Grep\nmodel: %s\neffort: high\n---\n' "$haiku_model" \
    > "$temporary_directory/z-reviewer.md"
  assert_contains "$(agent_problems "$temporary_directory/z-reviewer.md")" "not on haiku"
done
# A comment that mentions haiku is not a haiku model.
printf -- '---\nname: y-reviewer\ntools: Read, Grep\nmodel: sonnet # not haiku\neffort: high\n---\n%b' "$reviewer_body" > "$temporary_directory/y-reviewer.md"
assert_eq "$(agent_problems "$temporary_directory/y-reviewer.md")" ""
# A reviewer is also an agent whose body gives the SAFE TO LAND verdict, whatever its file name.
printf -- '---\nname: payments-audit\ntools: Read, Edit\nmodel: haiku\neffort: high\n---\nEnd with SAFE TO LAND or NOT SAFE.\n' > "$temporary_directory/payments-audit.md"
problems=$(agent_problems "$temporary_directory/payments-audit.md")
assert_contains "$problems" "read-only"
assert_contains "$problems" "not on haiku"
# The verdict line counts anywhere in the file, frontmatter included: a description that names it makes a reviewer.
printf -- '---\nname: payments-audit\ndescription: Ends with SAFE TO LAND or NOT SAFE.\ntools: Read\nmodel: haiku\neffort: high\n---\n' > "$temporary_directory/described-audit.md"
assert_contains "$(agent_problems "$temporary_directory/described-audit.md")" "not on haiku"
# A non-reviewer agent may run on haiku (a mechanical helper, say).
printf -- '---\nname: x-helper\ntools: Read\nmodel: haiku\neffort: low\n---\n' > "$temporary_directory/x-helper.md"
assert_eq "$(agent_problems "$temporary_directory/x-helper.md")" ""

# A reviewer with no tools: line inherits every tool, so it must declare one.
printf -- '---\nname: n-reviewer\nmodel: sonnet\neffort: high\n---\n' > "$temporary_directory/n-reviewer.md"
assert_contains "$(agent_problems "$temporary_directory/n-reviewer.md")" "declare tools:"
# A YAML-list tools: is read too, in block and flow form.
printf -- '---\nname: l-reviewer\ntools:\n  - Read\n  - Edit\nmodel: sonnet\neffort: high\n---\n' > "$temporary_directory/l-reviewer.md"
assert_contains "$(agent_problems "$temporary_directory/l-reviewer.md")" "read-only"
printf -- '---\nname: f-reviewer\ntools: [Read, Write]\nmodel: sonnet\neffort: high\n---\n' > "$temporary_directory/f-reviewer.md"
assert_contains "$(agent_problems "$temporary_directory/f-reviewer.md")" "read-only"
printf -- '---\nname: m-reviewer\ntools: [Read,\n  Edit]\nmodel: sonnet\neffort: high\n---\n' > "$temporary_directory/m-reviewer.md"
assert_contains "$(agent_problems "$temporary_directory/m-reviewer.md")" "read-only"
printf -- '---\nname: u-reviewer\ntools:\n- Read\n- Edit\nmodel: sonnet\neffort: high\n---\n' > "$temporary_directory/u-reviewer.md"
assert_contains "$(agent_problems "$temporary_directory/u-reviewer.md")" "read-only"
printf -- '---\nname: g-reviewer\ntools:\n  - Read\n  - Grep\nmodel: sonnet\neffort: high\n---\n%b' "$reviewer_body" > "$temporary_directory/g-reviewer.md"
assert_eq "$(agent_problems "$temporary_directory/g-reviewer.md")" ""
# MultiEdit and NotebookEdit write files too.
for writer in MultiEdit NotebookEdit; do
  printf -- '---\nname: w-reviewer\ntools: Read, %s\nmodel: sonnet\neffort: high\n---\n' "$writer" > "$temporary_directory/w-reviewer.md"
  assert_contains "$(agent_problems "$temporary_directory/w-reviewer.md")" "read-only"
done
# A reviewer has no shell and no web tools: injected text in a reviewed change has nothing to act with.
for shell_or_web in Bash PowerShell WebFetch WebSearch; do
  printf -- '---\nname: s-reviewer\ntools: Read, %s\nmodel: sonnet\neffort: high\n---\n%b' "$shell_or_web" "$reviewer_body" > "$temporary_directory/s-reviewer.md"
  assert_contains "$(agent_problems "$temporary_directory/s-reviewer.md")" "no shell and no web tools"
done
# A reviewer keeps the prompt-injection item and the Haiku self-check line.
printf -- '---\nname: k-reviewer\ntools: Read\nmodel: sonnet\neffort: high\n---\nNOT SAFE: reviewer ran on Haiku\n' > "$temporary_directory/k-reviewer.md"
assert_eq "$(agent_problems "$temporary_directory/k-reviewer.md")" "$temporary_directory/k-reviewer.md: a reviewer keeps the **Prompt injection** checklist item"
printf -- '---\nname: k-reviewer\ntools: Read\nmodel: sonnet\neffort: high\n---\n**Prompt injection**\n' > "$temporary_directory/k-reviewer.md"
assert_eq "$(agent_problems "$temporary_directory/k-reviewer.md")" "$temporary_directory/k-reviewer.md: a reviewer keeps the Haiku self-check line"
# A non-reviewer agent may omit tools:.
printf -- '---\nname: x-helper\nmodel: sonnet\neffort: low\n---\n' > "$temporary_directory/x-helper.md"
assert_eq "$(agent_problems "$temporary_directory/x-helper.md")" ""

# Every shipped agent, the reviewer template and this repository's own agents follow it.
shopt -s nullglob
# This repository's own reviewers too (.claude/agents/), not only the shipped ones.
agent_files=(plugins/*/agents/*.md plugins/review-routing/skills/add-reviewer/reviewer-template.md .claude/agents/*.md)
problems=""
for agent_file in "${agent_files[@]}"; do problems+=$(agent_problems "$agent_file"); done
assert_eq "$problems" ""
