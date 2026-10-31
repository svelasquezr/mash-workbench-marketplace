# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
guard="$PWD/plugins/review-routing/hooks/haiku-reviewer-guard.py"
hooks_json="$PWD/plugins/review-routing/hooks/hooks.json"

# hook <tool_name> <subagent_type> <model> <prompt>: feeds the PreToolUse JSON for an agent call to the guard.
# An empty model or subagent_type leaves that parameter out.
hook() {
  local payload
  payload=$(python3 -c '
import json, sys
name, kind, model, prompt = sys.argv[1:5]
params = {"prompt": prompt, "description": "check"}
if kind: params["subagent_type"] = kind
if model: params["model"] = model
print(json.dumps({"tool_name": name, "tool_input": params}))' "$1" "$2" "$3" "$4")
  run_capturing python3 "$guard" <<< "$payload"
}
blocked() { hook "$@"; assert_eq "$captured_exit_code" "2"; [[ -n "$captured_output" ]] || { echo "  no reason given for: $*"; exit 1; }; }
allowed() { hook "$@"; if [[ "$captured_exit_code" != 0 ]]; then printf '  expected allowed: %s\n  got %s: %s\n' "$*" "$captured_exit_code" "$captured_output"; exit 1; fi; }

# Registered for both tool names.
assert_contains "$(cat "$hooks_json")" '"matcher": "Agent|Task"'
assert_contains "$(cat "$hooks_json")" 'haiku-reviewer-guard.py'

# A reviewer on Haiku, by name, with the reason naming the rule and both models.
blocked Agent review-routing:change-reviewer haiku "review the diff"
assert_contains "$captured_output" "never run on Haiku"
assert_contains "$captured_output" "launched on \`haiku\`"
assert_contains "$captured_output" "reviewers-for-change.py --pr N --models"
assert_contains "$captured_output" "review-pr skill directory"
assert_contains "$captured_output" "pass no \`model\`"
assert_contains "$captured_output" "frontmatter (Sonnet for review-routing:change-reviewer)"
blocked Task my-security-reviewer HAIKU "review the diff"
# A full model id.
blocked Agent review-routing:change-reviewer claude-haiku-4-5-20251001 "review the diff"
# Not named a reviewer, but the prompt carries a reviewer marker (fix-round re-checks).
blocked Agent general-purpose haiku "Re-verify the fix. End with SAFE TO LAND or NOT SAFE."
blocked Agent general-purpose haiku "Findings are grouped Critical / Important / Minor"
blocked Agent "" haiku "verdict: NOT SAFE"
blocked Task general-purpose haiku "Re-check; end with SAFE TO LAND or NOT SAFE"

# Allowed.
allowed Agent review-routing:change-reviewer sonnet "review the diff"
allowed Agent review-routing:change-reviewer "" "review the diff"
allowed Agent Explore haiku "find the config loader"
allowed Agent general-purpose haiku "summarise the README"
# Near misses: half of the group header is not a marker.
allowed Agent general-purpose haiku "Critical bugs only, please"
allowed Agent general-purpose haiku "Important: summarise the notes"
# Malformed input: not JSON, wrong shapes, missing fields.
run_capturing python3 "$guard" <<< "not json"; assert_eq "$captured_exit_code" "0"
run_capturing python3 "$guard" <<< ""; assert_eq "$captured_exit_code" "0"
run_capturing python3 "$guard" <<< '{"tool_name": "Agent"}'; assert_eq "$captured_exit_code" "0"
run_capturing python3 "$guard" <<< '{"tool_name": "Agent", "tool_input": "x"}'; assert_eq "$captured_exit_code" "0"
run_capturing python3 "$guard" <<< '{"tool_name": "Agent", "tool_input": {"model": 5, "subagent_type": ["reviewer"]}}'; assert_eq "$captured_exit_code" "0"
run_capturing python3 "$guard" <<< '[1]'; assert_eq "$captured_exit_code" "0"
# Another tool is never judged.
allowed Bash review-routing:change-reviewer haiku "SAFE TO LAND"

# An agent whose prompt only quotes words from the markers is not a review (and is not refused).
allowed Agent general-purpose haiku "Summarise this doc. It says the API is NOT SAFE for children."
allowed Agent Explore haiku "Find where severities Critical / Important are defined."

# Both registered hook commands do nothing, quietly, when python3 is not on the PATH, and run the hook when it is.
for hook_script in haiku-reviewer-guard.py reviewer-guard.py; do
  command_line=$(python3 - "$hooks_json" "$hook_script" <<'PY'
import json, sys
for group in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    for entry in group["hooks"]:
        if sys.argv[2] in entry["command"]:
            print(entry["command"])
PY
)
  [[ -n "$command_line" ]] || { echo "  no hook command for $hook_script"; exit 1; }
  run_capturing env -i PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$PWD/plugins/review-routing" /bin/sh -c "$command_line" <<< '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
  assert_eq "$captured_exit_code" "0"
  assert_eq "$captured_output" ""
done
haiku_command=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$hooks_json")
run_capturing env CLAUDE_PLUGIN_ROOT="$PWD/plugins/review-routing" sh -c "$haiku_command" <<< '{"tool_name":"Agent","tool_input":{"model":"haiku","subagent_type":"x-reviewer","prompt":"review"}}'
assert_eq "$captured_exit_code" "2"
