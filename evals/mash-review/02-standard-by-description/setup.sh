# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p src
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 - discount)\n' > src/billing.py
mkdir -p .claude/skills/review-billing
cat > .claude/skills/review-billing/SKILL.md <<'SKILL'
---
name: review-billing
description: Use when reviewing a change to prices, discounts, taxes or order totals
---

# Review: billing

Model: sonnet

## Project checks

- A discount is a fraction between 0 and 1 and lowers the total; it never raises it.

## Not checked here

- Formatting: the formatter enforces it.
SKILL
git add -A
git commit -q -m "add billing total"
git switch -q -c feature
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 + discount)\n' > src/billing.py
git commit -q -am "apply the discount to the total"
