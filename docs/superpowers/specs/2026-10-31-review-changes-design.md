# Design: `review-changes` (pre-PR self-review) and grouped MASH ledgers

Status: approved by the user on 2026-10-31. PR 1 implements the first half (review-changes); PR 2 (ledgers under `docs/mash/`) follows as a separate stacked PR.

## Intent
`review-pr` (plugin `review-routing`) tries to do everything:
- open the PR;
- route reviewers;
- review;
- post comments;
- file issues;
- squash-merge.

That doesn't match how teams work: humans, CODEOWNERS and branch protection own the PR. It also ties the whole plugin to GitHub through `gh`. The part with real value is **before** the PR exists: a developer asks the agent to review their own changes with the right reviewers, routed by `.claude/reviewers.toml`, and fixes what they find. Claude Code is used with many git hosts, so the review needs **git only**.

So we fix forward. This replaces the earlier plan to remove review-pr and park it in a draft PR.

## Goals
- A skill, `review-changes`, reviews the developer's own changes before they open a PR, using only git.
- The `review-routing` plugin no longer depends on `gh`.
- Both plugins' ledgers (`review-escapes.md`, `tooling-backlog.md`) live together under `docs/mash/`. Their location can be changed, they can be switched off, and the skill offers to gitignore each one when it first creates it.

## Non-goals (future, separate skills)
- A `gh` code-review skill that posts inline PR comments.
- A PR babysitter (watches CI, addresses review comments), possibly an orchestrator.
- Reviewing someone else's PR.

## Anti-goals
- The skill pushes, opens or comments on PRs, files issues, or merges.
- It assumes a host, a merge strategy, or one-PR-per-change.
- It runs a check command it guessed without the user confirming it.
- A clean verdict hides that no automated checks ran.

## PR 1: `review-changes` replaces `review-pr`

### The skill (`plugins/review-routing/skills/review-changes/SKILL.md`)
Under about 500 words, and the description lists only triggers: "before opening a PR", "review my changes", "self-review".

**Flow:**
0. **Escape fix (kept from review-pr, one line).** If this change fixes a bug in code a review had passed, ask for its issue link and record it with `escape-add.sh`.
1. **Range.** The default is `<default branch>...HEAD`, and the user can name another base. Only committed work is reviewed *(my call)*. If the tree has uncommitted changes, the skill asks the user to commit them first. Fix rounds need a commit to diff from, and `[[changed_lines]]` and the model rules need a range. It routes with `route <range> --models`, and dispatches every agent the script prints, on the models it prints. The same rules hold as today:
   - a non-zero exit is an error, never "no reviewers";
   - `-` means the agent's own default (`sonnet` for `general-purpose`);
   - with no `.claude/reviewers.toml`, it uses `change-reviewer` alone and points to add-reviewer;
   - `route --check` runs when the change touches `.claude/reviewers.toml` or `.claude/agents/`.
2. **Checks first, as a gate.**
   - If CLAUDE.md or AGENTS.md names test, lint and format commands, it runs them.
   - Otherwise it runs `find-checks` (below), proposes the commands it found, and runs them only after the user confirms. It then offers to add one line naming them to CLAUDE.md.
   - If nothing exists, the review runs anyway. Reviewers are told "no automated checks ran", every mechanical finding comes with "add the tool that catches it", and the summary says **Unchecked: no tests or linters configured**.
   - Failing checks are fixed before any reviewer runs.
3. **Dispatch all reviewers in parallel.** Each prompt contains:
   - the range to diff (`git diff <range>`);
   - the intent of the change in one or two sentences;
   - the check results;
   - anything the agent's description says the caller must name.

   The general-purpose fallback preamble (read-only, severity groups, the exact `SAFE TO LAND` / `NOT SAFE:` rule) is kept word for word.
4. **Triage.**
   - Mechanical findings are fixed, and the tool that would have caught them is added (or proposed). With mash-workbench installed, each also becomes a scout candidate.
   - Problems this change introduced are fixed in new commits. Only the fix diff (`git diff <noted head> HEAD`) goes back, to the reviewers `route <noted head>..HEAD` names plus those that found something, on the models step 1 gave them. After two fix rounds still `NOT SAFE`, it stops and reports.
   - Findings the agent disputes are answered with evidence in the next round.
   - Pre-existing problems are **listed for the user**, not filed.
   - For an escape (`escape: yes`), it records the bug with `escape-add.sh` once the user gives an issue link (any host).
5. **Terminal summary only.** It prints:
   - each reviewer's last verdict, finding counts and fix rounds;
   - the checks that ran, or the "Unchecked" line;
   - Minor suggestions left open;
   - pre-existing findings;
   - "ready to open your PR", or the open findings.

   Nothing is written to a PR.

`reference.md` *(my call: it can hold more than escapes)* holds:
- "Recording escapes", rewritten without `gh`;
- the fix-round diff rule for when the default branch was merged in;
- the common-mistakes table;
- anything else that doesn't fit in 500 words.

The "Review round comments" section and the "Review verdicts" PR comment are dropped. A gitignored escape ledger is updated but never committed.

### Reviewer agents (git-only too, my call)
- **The prompt.** `change-reviewer.md` and `reviewer-template.md` start from `git diff <range>`, not `gh pr diff N`.
- **The Pre-existing group.** It becomes "Pre-existing (to file as issues)", with no "ready for `gh issue create`".
- **Projects that already copied the template** keep working. Their wording is only out of date, and the README says so.
- **`reviewer-guard.py`** keeps blocking reviewers' `gh` write commands. That is protection, not a dependency, so its README row, `hooks.json` and tests stay as they are. The verification grep allows these mentions.

### Scripts
- **Move** `reviewers-for-change.py` and `route_*.py` from `skills/review-pr/` into `skills/review-changes/`. Scripts stay next to their skill, as ADR 0001 requires. The other skills already reach them through `../<skill>/`.
- **Remove `--pr`:**
  - the `change_in_pull_request` and `pull_request_title` functions in `route_change.py`;
  - the argparse option and its branches in `reviewers-for-change.py`;
  - the fake-`gh` harness and `--pr` cases in `tests/test_reviewers_for_change.sh`.

  `[[model_rules]] title_pattern` keeps working from the range's commit subjects (`range_facts`). Check its docs and `--help` text: anything that said "PR title" now means commit subjects.
- **New `find-checks.sh <repo-root>`** in `skills/review-changes/`, with its bash test written first. It prints candidate check commands, one per line, each with the file it came from, read from:
  - `package.json` scripts named test, lint, format, typecheck or check;
  - `Makefile` or `justfile` targets with those names;
  - `pyproject.toml` (tool sections for pytest, ruff, mypy);
  - `.pre-commit-config.yaml` (`pre-commit run --all-files`);
  - `.github/workflows/*.yml`, `.gitlab-ci.yml` and other CI files: the `run:` / `script:` lines.

  It exits 0 with nothing printed when it finds nothing. It only lists commands and never runs them.

### Everything that named review-pr
- **Skills and agents** (add-reviewer `SKILL.md` and `reference.md`, inspect `SKILL.md` and `reference.md`, the `change-reviewer` agent, the reviewer template): `review-pr` becomes `review-changes`, and the `../review-pr/` script paths become `../review-changes/`.
- **inspect's rule** becomes "a code change is reviewed through the review-changes skill before its PR".
- **inspect's merge-flow lines** go away; it no longer needs to leave merge rules alone.
- **Hooks:** the haiku-reviewer-guard message and docstring, and the `reviewer-guard.py:42` mention. The tests change with them: `test_haiku_reviewer_guard.sh`, `test_escapes.sh`, and `test_reviewer_verdict.sh` (its fallback checks now point at `review-changes/SKILL.md`).
- **README:**
  - the `review-changes` row says what it does;
  - Requirements: `git`, `bash` and `python3` 3.11+, and **no `gh`**; escape links from GitHub are normalised, and other links are kept as given;
  - the squash-merge default is removed;
  - "What it writes" loses PR comments, issues and merges.
- **Plugin description** (`plugin.json` and both `marketplace.json` files, kept identical): "route each change to its reviewers from .claude/reviewers.toml, review your changes before opening a PR, add a reviewer, ready an existing project (inspect)". Version `0.1.0` → `0.2.0`.

## PR 2: ledgers grouped under `docs/mash/`
- **Default location** `docs/mash/tooling-backlog.md` and `docs/mash/review-escapes.md`. The setting variables follow the existing `MASH_WORKBENCH_BACKLOG` pattern in `plugins/mash-workbench/skills/scout/backlog-path.sh`:
  - a path (relative to the repo root) moves the ledger;
  - `off` turns it off;
  - unset uses the default when that file exists;
  - nothing is created until the user chooses (exit 3).
- **Escape ledger.** A new `escapes-path.sh` in add-reviewer, with the variable `REVIEW_ROUTING_ESCAPES`. `escape-add.sh` and `escapes-report.sh` use it instead of the hardcoded `docs/review-escapes.md`. When the ledger is `off`, `escape-add.sh` records nothing and says so.
- **Backward compatible.** If the variable is unset and only the old file exists (`docs/tooling-backlog.md` or `docs/review-escapes.md`), that old file is still used. The skill offers to `git mv` it into `docs/mash/` and never moves it on its own.
- **Gitignore offer.** When a skill first creates a ledger, it offers to add the file to `.gitignore`. It says plainly that an ignored ledger counts only that developer's entries. The default and recommendation is to commit it.
- Both plugins' READMEs and skills are updated, and every script change gets its test first. Both plugins' versions are bumped.

## Constraints
- Repo rules in AGENTS.md:
  - every script gets a bash test written first;
  - `bash scripts/check.sh` and `uvx pre-commit run --all-files` stay green;
  - Conventional Commits;
  - a SKILL.md stays under about 500 words, and its frontmatter has only `name` and `description`;
  - Python 3.11+;
  - bash that also runs on 3.2 (macOS).
- **Shipping (my call).**
  - The agent pushes and opens both PRs.
  - PR 2 is stacked on PR 1's branch: its base is `review-changes`. After PR 1 squash-merges, PR 2 is rebased onto main.
  - Versions: review-routing goes to 0.2.0 in PR 1 and 0.3.0 in PR 2; mash-workbench gets a minor bump in PR 2.
- Each PR: Fable reviews it (`review-routing:change-reviewer`, `model: fable`). The fixes go in new commits. Then Opus re-checks the PR with Fable's findings and how each was handled. Neither PR is merged by the agent.

## Left to the builder
- The exact wording of the skill and the summary layout.
- The `find-checks.sh` parsing details: best-effort, and it never fails.
- How the default branch is found (`origin/HEAD`, else `main`/`master`, else ask).

## Verification
- `bash scripts/check.sh` and `uvx pre-commit run --all-files` pass.
- `grep -rn "review-pr\|--pr\|\bgh " plugins/review-routing` matches only `reviewer-guard`'s refusal of `gh` writes (and its tests and docs).
- With `claude --plugin-dir plugins/review-routing` in a scratch repo:
  - `/review-routing:review-changes` runs on a branch with and without `.claude/reviewers.toml`;
  - with and without checks configured, the summary shows "Unchecked" in the no-checks case.
- PR 2: with the scratch repo holding the old `docs/tooling-backlog.md`, it's still used and a move is offered; a fresh repo gets nothing until the user chooses.
