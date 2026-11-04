# shellcheck shell=bash
# The forge skill's "Earlier sessions" command, taken verbatim from its reference.md and run on a fixture history:
# it keeps this project's corrections, and never prints pasted contents or other projects' prompts.
set -euo pipefail
source tests/lib.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT

# The one fenced block in the reference is the command.
recipe=$(awk '/^```/ { inside = !inside; next } inside' plugins/mash-workbench/skills/forge/reference.md)
assert_contains "$recipe" 'history.jsonl'

cat > "$temporary_directory/history.jsonl" <<'JSONL'
{"display":"No, use uv not pip","pastedContents":{},"timestamp":1791100000000,"project":"/work/app","sessionId":"s1"}
{"display":"please add a test","pastedContents":{"1":{"content":"No, SECRET=abc123"}},"timestamp":1791100001000,"project":"/work/app","sessionId":"s1"}
{"display":"I told you to run the linter first","pastedContents":{"1":{"content":"token ghp_PASTED"}},"timestamp":1791200000000,"project":"/work/app","sessionId":"s2"}
{"display":"you forgot the changelog again","pastedContents":{},"timestamp":1791300000000,"project":"/work/app","sessionId":"s3"}
{"display":"don't use pip please","pastedContents":{},"timestamp":1,"sessionId":"s4","project":"/work/app"}
{"display":"no, other project","pastedContents":{},"timestamp":1791300000000,"project":"/work/other","sessionId":"s9"}
{"display":"no, a project whose path starts the same","pastedContents":{},"timestamp":1,"project":"/work/app-old","sessionId":"s8"}
{"display":"thanks, looks good","pastedContents":{},"timestamp":1,"project":"/work/app","sessionId":"s5"}
JSONL

output=$(CLAUDE_CONFIG_DIR="$temporary_directory" bash -c "${recipe//<root>//work/app}")
# This project's corrections, including one whose project field comes last.
assert_contains "$output" '"display":"No, use uv not pip'
assert_contains "$output" '"display":"I told you to run the linter first'
assert_contains "$output" '"display":"you forgot the changelog again'
assert_contains "$output" "\"display\":\"don't use pip please"
assert_contains "$output" '"sessionId":"s2"'
# Never pasted contents, other projects, or prompts that are not corrections.
assert_not_contains "$output" 'SECRET'
assert_not_contains "$output" 'ghp_PASTED'
assert_not_contains "$output" 'other project'
assert_not_contains "$output" 'starts the same'
assert_not_contains "$output" 'looks good'
assert_not_contains "$output" 'please add a test'

# A missing history file prints nothing and does not stop the skill with an error message it must parse.
empty_output=$(CLAUDE_CONFIG_DIR="$temporary_directory/none" bash -c "${recipe//<root>//work/app}" 2>/dev/null || true)
assert_eq "$empty_output" ""
