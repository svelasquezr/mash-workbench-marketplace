# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
reviewer=plugins/mash-review/agents/reviewer.md

# SAFE TO LAND is only for a change with suggestions and no bugs: Critical or Important blocks it.
verdict_rule=$(cat "$reviewer")
assert_contains "$verdict_rule" "only when there are no Critical and no Important findings"
assert_contains "$verdict_rule" "Minor findings are suggestions and do not block"
assert_not_contains "$verdict_rule" "(the first three groups)"
assert_contains "$verdict_rule" "NOT SAFE: <why>"
assert_contains "$verdict_rule" "judged on this change as it stands"

# A promised later fix does not make a finding safe.
assert_contains "$verdict_rule" "even when the author says it will be fixed later"
