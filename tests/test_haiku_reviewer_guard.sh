# shellcheck shell=bash
# The review-routing plugin's only hook: an inline shell command in hooks.json (no script file) that denies a
# reviewer agent launched on Haiku. This test feeds it hook input the way Claude Code does (JSON on stdin) and
# checks its exit code: 2 denies the Agent call, 0 lets it through. It must fail open on anything unexpected.
set -euo pipefail
source tests/lib.sh
hooks_file=plugins/review-routing/hooks/hooks.json

# Exactly one hook, on the Agent tool (Task is its older name).
assert_eq "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["hooks"]), len(d["hooks"]["PreToolUse"]), d["hooks"]["PreToolUse"][0]["matcher"])' "$hooks_file")" "1 1 Agent|Task"
hook_command=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$hooks_file")

# exit_code_for <stdin>: the command's exit code for that hook input (Claude Code runs it with sh).
exit_code_for() {
  local code=0
  printf '%s' "$1" | sh -c "$hook_command" >/dev/null 2>&1 || code=$?
  echo "$code"
}

# Denied: a reviewer, by name or by the verdict words in its prompt, on any Haiku spelling.
assert_eq "$(exit_code_for '{"tool_name":"Agent","tool_input":{"subagent_type":"review-routing:change-reviewer","model":"haiku","prompt":"x"}}')" 2
assert_eq "$(exit_code_for '{"tool_input": {"model": "claude-haiku-5-5", "subagent_type": "payments-reviewer"}}')" 2
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"general-purpose","model":"Haiku","prompt":"end with SAFE TO LAND"}}')" 2
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"x","model":"haiku","prompt":"group as Critical / Important / Minor"}}')" 2

# The refusal says what to do instead.
reason=$(printf '%s' '{"tool_input":{"subagent_type":"a-reviewer","model":"haiku"}}' | sh -c "$hook_command" 2>&1 >/dev/null || true)
assert_contains "$reason" "dispatch on sonnet, opus or fable"

# Allowed: a reviewer on another model, a non-reviewer on Haiku, a prompt that only quotes the words.
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"payments-reviewer","model":"sonnet","prompt":"SAFE TO LAND"}}')" 0
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"Explore","model":"haiku","prompt":"find the config files"}}')" 0
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"x-reviewer","prompt":"later set \"model\":\"haiku\""}}')" 0
assert_eq "$(exit_code_for '{"tool_input":{"subagent_type":"x","model":"haiku","prompt":"the reviewer said hello"}}')" 0
# Fails open: empty input, input that is not JSON, and a shell without grep.
assert_eq "$(exit_code_for '')" 0
assert_eq "$(exit_code_for 'not json at all')" 0
code=0
printf '%s' '{"tool_input":{"subagent_type":"a-reviewer","model":"haiku"}}' | PATH=/nonexistent /bin/sh -c "$hook_command" >/dev/null 2>&1 || code=$?
assert_eq "$code" 0
