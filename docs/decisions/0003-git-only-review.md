# 0003: review-routing needs only git

## Context
`review-pr` opened pull requests, posted comments, filed issues and squash-merged, all through `gh`. Claude Code is used with many git hosts, and in teams people, CODEOWNERS and branch protection own the pull request.

## Decision
`review-changes` reviews committed work before a pull request exists, uses only git, and prints its summary in the terminal. It never pushes, opens a PR, comments, files issues or merges. The routing script lost `--pr`. Reviewing someone else's PR with inline comments, and babysitting a PR, are future skills.

## Pros and cons
- Pros: works on any host; no merge-strategy assumptions; no noise on the PR; one fewer external dependency.
- Cons: no review record on the PR (the reviewer-written findings live in the session); a future `gh` skill must re-implement `--pr` routing, recoverable from git history; `reviewer-guard` still refuses `gh` writes by reviewers, as protection.
- `find-checks.sh` lists candidate checks but the user confirms before anything runs: a guessed command could do harm; the cost is one question.
