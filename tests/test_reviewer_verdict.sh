# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh

# Every reviewer the plugin ships, the template a new specialist copies, and this repository's own reviewers
# state the same verdict rule: SAFE TO LAND is only for a change with suggestions and no bugs.
for reviewer in plugins/review-routing/agents/change-reviewer.md \
  plugins/review-routing/skills/add-reviewer/reviewer-template.md .claude/agents/*-reviewer.md; do
  text=$(cat "$reviewer")
  assert_contains "$text" "only when there are no Critical and no Important findings"
  assert_contains "$text" "Minor findings are suggestions and do not block"
  # A promised later fix does not make a finding safe.
  assert_contains "$text" "even when the author says it will be fixed later"
  # Exactly one verdict line, so review-changes can read it.
  assert_contains "$text" "End with exactly one line, judged on this change as it stands"
  assert_not_contains "$text" "(the first three groups)"
done

# general-purpose has no verdict format and every tool, so routing refuses it as a reviewer.
# shellcheck disable=SC2016  # the backticks are literal Markdown
assert_contains "$(cat plugins/review-routing/skills/review-changes/reference.md)" 'when a reviewer is `general-purpose`'
