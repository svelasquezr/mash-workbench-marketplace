# 0002. Dependabot for GitHub Actions and pre-commit hooks

## Status
Accepted.

## Context
Every external dependency is pinned to an exact version: actions in `.github/workflows/ci.yml` and hook revs in `.pre-commit-config.yaml`. Nothing kept those pins current. The repo has no npm or pip manifests, so the only ecosystems are `github-actions` and `pre-commit`. CI checks commit messages with `cz check`, so automated PR titles must be Conventional Commits.

## Decision
`.github/dependabot.yml` runs weekly for both ecosystems, grouping each into one PR. Commit prefixes are `ci(deps)` for actions and `chore(deps)` for hooks, which pass the commit check.

Dependabot over Renovate:
- Pros: built into GitHub, no app to install or permissions to grant.
- Cons: it cannot update versions pinned inside `run:` lines, and has fewer grouping and regex options.

## Consequences
- Not covered, update by hand: `@anthropic-ai/claude-code@…`, the `setup-uv` `version:`, and the `commitizen==…` and `pre-commit@…` pins in `ci.yml`.
- Known drift: commitizen is pinned in both `.pre-commit-config.yaml` (Dependabot bumps it) and `ci.yml` (it does not). Whoever merges the pre-commit PR bumps the `ci.yml` pin to match.
- To revisit when: more of the pins move into files Dependabot understands, or the manual list grows painful (then consider Renovate).
