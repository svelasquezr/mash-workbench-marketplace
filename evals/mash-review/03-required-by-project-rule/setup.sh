# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p src
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 - discount)\n' > src/billing.py
mkdir -p .claude/skills/review-security
cat > .claude/skills/review-security/SKILL.md <<'SKILL'
---
name: review-security
description: Use when reviewing a change to login, sessions, tokens or permissions
---

# Review: security

## Project checks

- No secret, token or password is written to a log.
SKILL
cat > CLAUDE.md <<'RULES'
# Project rules

A change under `src/` always gets the `review-security` standard.
RULES
git add -A
git commit -q -m "add billing total"
git switch -q -c feature
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 + discount)\n' > src/billing.py
git commit -q -am "apply the discount to the total"
