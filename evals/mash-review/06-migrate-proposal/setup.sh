# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p src
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 - discount)\n' > src/billing.py
mkdir -p .claude/agents .claude/mash-workbench/escapes
cat > .claude/reviewers.toml <<'TOML'
default_model = "opus"

[[routes]]
pattern = '^src/billing'
reviewers = ["billing-reviewer"]
reason = "moves money"

[[changed_lines]]
path_pattern = '^requirements\.txt$'
line_pattern = 'payments-sdk'
reviewers = ["billing-reviewer"]

[[fallbacks]]
pattern = '\.md$'
reviewers = ["review-routing:change-reviewer"]

[[model_rules]]
reviewer = "billing-reviewer"
model = "opus"
path_pattern = '^src/billing'
TOML
cat > .claude/agents/billing-reviewer.md <<'AGENT'
---
name: billing-reviewer
description: Reviews changes to billing
tools: Read, Grep, Glob, Bash
model: sonnet
---

## Checklist

- A discount lowers the total; it never raises it.
AGENT
printf 'escapes=.claude/mash-workbench/escapes\nbacklog=docs/team-backlog.md\n' > .claude/mash-workbench/settings
printf -- '---\ndate: 2026-10-01\narea: src/billing\nclass: wrong-result\n---\n\nWhen the order has a discount, the total includes tax. The total must not include tax.\n' > .claude/mash-workbench/escapes/2026-10-01-discount-tax.md
git add -A
git commit -q -m "review-routing setup"
cat > .claude/settings.local.json <<'JSON'
{"permissions": {"allow": ["Bash(bash */review-routing/*add-reviewer/escape-add.sh*)"]}}
JSON
printf 'abc123 def456\n' > .claude/mash-workbench/reviews.log
printf '.claude/mash-workbench/reviews.log\n.claude/settings.local.json\n' >> .git/info/exclude
