# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
reviewer=plugins/review-routing/agents/change-reviewer.md

# SAFE TO LAND is only for a change with suggestions and no bugs: Critical or Important blocks it.
verdict_rule=$(cat "$reviewer")
assert_contains "$verdict_rule" "only when there are no Critical and no Important findings"
assert_contains "$verdict_rule" "Minor findings are suggestions and do not block"
assert_not_contains "$verdict_rule" "(the first three groups)"

# The template a new specialist copies, and the general-purpose fallback prompt, state the same rule.
template=$(cat plugins/review-routing/skills/add-reviewer/reviewer-template.md)
assert_contains "$template" "only when there are no Critical and no Important findings"
assert_contains "$template" "Minor findings are suggestions and do not block"
fallback=$(cat plugins/review-routing/skills/review-pr/SKILL.md)
assert_contains "$fallback" "only when there are no Critical and no Important findings"

# Every place states the clause that a promised later fix does not make a finding safe, and the fallback states the Minor rule too.
assert_contains "$verdict_rule" "even when the author says it will be fixed later"
assert_contains "$template" "even when the author says it will be fixed later"
assert_contains "$fallback" "even when the author says it will be fixed later"
assert_contains "$fallback" "Minor findings are suggestions and do not block"

# The fallback prompt asks for exactly one verdict line, so tools can read it.
assert_contains "$fallback" "end with exactly one line, judged on this change as it stands"
