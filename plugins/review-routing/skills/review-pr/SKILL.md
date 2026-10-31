---
name: review-pr
description: Use when a pull request or branch is pushed and ready for review before landing, or when deciding which reviewer agents a change needs
---

# Review a pull request with routed reviewer agents

Every change is reviewed by the agents for its kinds of change. Which agents is decided by the project's routing config (`.claude/reviewers.toml`) through a script, not from memory: a change that touches four areas needs four reviewers. Below, `route` means `python3 <this skill's base directory>/reviewers-for-change.py`, run from the repository (Python 3.11+, standard library only; `route --help` shows every option).

**Reviewers judge; tools enforce.** Anything a test, linter, formatter, type checker or hook can decide (style, formatting, import order, types, a banned pattern, a missing file, a convention) belongs in automation that runs in CI and pre-commit, not in a reviewer's attention. A reviewer spends tokens on what only judgment catches: intent, invariants across files, edge cases, missing tests for new branches. If the project's CLAUDE.md names no test, lint and format commands, say so to the user before reviewing: the deterministic gate below has nothing to run.

**No `.claude/reviewers.toml` yet:** `route` prints `review-routing:change-reviewer` alone and notes on stderr that the config is missing; review with it, and tell the user that the add-reviewer skill sets up routing. If the project's main branch has the file, this checkout is stale: update it first, or its specialists are skipped. Don't add the config inside this PR.

## Steps

0. **A fix for a bug in code a review passed?** If so, record its issue (a fix PR with no `Closes #N` files the issue first), keyed by that issue link, and commit the ledger change in this PR (`escape-add.sh`; "Recording escapes" in `reference.md`).
1. **Push and open the PR first** (`git push -u` and `gh pr create`), then pick the reviewers and their models: `route --pr N --models` prints `agent<TAB>model` lines. Dispatch every agent it prints, using each name as the `subagent_type` exactly as printed (`review-routing:change-reviewer` included), and pass its model as the call's `model` unless it is `-` (then the agent's own default applies; `general-purpose` has none, so pass `sonnet`). (`route origin/main...HEAD`, three dots, only previews an unpushed branch.) A non-zero exit means the range, the PR number or the config is wrong: fix it, never treat it as "no reviewers". When the PR touches `.claude/reviewers.toml` or `.claude/agents/`, also run `route --check` and report its result with the other checks.

   Then show the routing on the PR, so the user sees who reviews what and why: write `route --pr N --explain --format markdown` (it starts with a "Review routing" heading) to a file outside the repository and post it with `gh pr comment N --body-file <file>`. It is a comment, so each review round keeps its own routing record and the author's description stays with the author.
2. **Deterministic checks first, once, as a gate:** read CI (`gh pr checks N`), or while it is still running use your own run of the full test suite, linters, formatters and type checks (the commands in the project's CLAUDE.md). Reviewers do not run them. Any failure is fixed and pushed before step 3: a reviewer never sees a red build, and a tool's verdict is never replaced by a reviewer's opinion.
3. **Dispatch all reviewers in one message** (parallel). Each prompt holds, in order:
   - only if the script printed `general-purpose` (a project config that still names it), first: "read-only: do not edit files; group findings as Critical / Important / Minor / Pre-existing and end with exactly one line, judged on this change as it stands: `SAFE TO LAND` only when there are no Critical and no Important findings (Minor findings are suggestions and do not block); any Critical or Important finding gives `NOT SAFE: <why>`, even when the author says it will be fixed later";
   - the range: "review `gh pr diff N`";
   - what the change is for, in one or two sentences;
   - the check results, e.g. "suite: 612 passed; lint clean; don't re-run deterministic checks";
   - anything an agent's description says the caller must name (for example design documents it skips unless asked).

   Every reviewer agent defines its own focus, output groups and that verdict line in its agent file; don't restate them. A reviewer that errors or returns no verdict is dispatched again, on the model step 1 gave it; it never counts as safe.
4. **Triage every finding:**
   - a mechanical finding (formatting, style, types, a convention, anything a tool could have decided) → fix it, then close the gap so the next PR doesn't need a reviewer for it: add the test, lint rule, formatter setting or hook in this PR when it is small, else an issue. Say in the PR which check now covers it. If the project has the mash-workbench plugin, record it as a tooling candidate (its `scout` skill).
   - introduced (or made worse) by this PR → fix it in the PR, one round at a time:
     1. note `git rev-parse HEAD`;
     2. fix in a new commit (never an amend: the branch is not rewritten, and the squash merge gives main one commit), rerun the suite and linters, push;
     3. send `git diff <noted head> HEAD` (when main was merged in since: `git log -p --first-parent --no-merges <noted head>..HEAD` plus `git show` of each merge that `git log --first-parent --merges <noted head>..HEAD` lists, so main's commits don't pose as the fix) to every reviewer that `route <noted head>..HEAD` prints, plus every reviewer that found something. Not the whole PR again. Start each on the model step 1's `route --pr N --models` gave it (a reviewer new in this round: run `route --pr N --models` again). Never take models from the `..` range: it sees only the fix's commits, so a model rule for new features wouldn't hold.

     After two fix rounds that still end `NOT SAFE`, stop and report to the user with the open findings.
   - a bug a person, CI or a later reviewer found in code the reviewers had passed (an escape) → fix it like any finding, and record its issue link; commit the ledger change with the fix ("Recording escapes" in `reference.md`).
   - a finding you think is wrong → don't drop it silently: answer it with your evidence in the next round's prompt to that reviewer; its next verdict decides.
   - in code the PR didn't change (the reviewer's "Pre-existing" group) → an issue, not fix work. Write the body with the Write tool to a file outside the repository (for example in a folder from `mktemp -d`): an inline `--body` breaks on backticks and `$`, and hooks that scan command text can match words inside it. Run `gh issue create --title "<title>" --label <label> --body-file <file>` with the label the reviewer suggested (when the project uses labels), record each finding marked `escape: yes` by its issue link and put the report line `escape-add.sh` prints, if any, beside the issue links in the PR body (`gh pr edit N --body-file <file>`).
     Details: "Recording escapes" in `reference.md`. Don't start fixing those issues unless the user asks.

   Post each round on the PR right after its triage (fixes pushed, issues filed), so the findings reach GitHub, not only this session: layout in "Review round comments" in `reference.md`. The next round, or landing, comes after it; so does stopping after two fix rounds, whose last comment lists the open findings.
5. **Land** only when all of these hold:
   - every reviewer's last verdict is `SAFE TO LAND`;
   - every PR review comment (`gh pr view N --comments`) is addressed;
   - every CI check passed (pending, failing and skipped all block);
   - the user asked to land this change, or the project's CLAUDE.md gives a standing rule that reviewed changes land on their own.

   If the branch is behind its base, merge the base into it, re-run the tests and send any conflict resolution to the reviewers before landing. Then run `gh pr checks N --watch`, confirm every check passed, then `gh pr merge N --squash --delete-branch --match-head-commit <the head SHA the reviewers saw, or the ledger-only commit after it>`. If merging main changed code (a conflict resolved), send the resolution diff (`git show <merge commit>`) to the reviewers of those files before landing.

   Not asked to land: stop at the reviewed, green PR and report its URL with each reviewer's verdict.

   Either way, finish with one PR comment, headed "Review verdicts": one line per reviewer with its last verdict, its finding counts (Critical / Important / Minor) and the number of fix rounds, then a last line that tools can read, exactly `VERDICT: SAFE TO LAND` (every reviewer's last verdict is safe) or `VERDICT: NOT SAFE: <why>`.

## Common mistakes

| Mistake | Instead |
|---|---|
| Picking reviewers from the file names you remember | Run `route`; docs, scripts and `.claude/` may have reviewers too |
| Telling the user who reviewed without saying why | Post the `--explain --format markdown` routing comment |
| Reading a non-zero exit as "no reviewers needed" | Fix the range, PR number or config and run it again |
| Skipping `review-routing:change-reviewer` because "it's a small change" | Every agent the script prints is dispatched |
| Letting reviewers run the suite and linters | Run them once; pass the results in each prompt |
| Dispatching reviewers while a test, linter or formatter is red | Fix the deterministic failures first; reviewers see a green build |
| A reviewer flags formatting, style or a convention and the fix stops there | Automate it (test, lint rule, formatter, hook) so no reviewer has to catch it again |
| Findings left in the session, so the user can't read them on GitHub | Post each round on the PR after its triage (step 4) |
| Re-reviewing the whole PR after a small fix | Send the fix's diff to the reviewers step 4 names |
| Starting a fix-round reviewer without a model | Use the model `route --pr N --models` gave it in step 1 |
| Fixing an old bug a reviewer spotted inside this PR | File an issue; one concern per PR |
| Counting a reviewer that crashed or gave no verdict as safe | Dispatch it again |
| Landing because CI is green while a reviewer said `NOT SAFE` | Every reviewer's last verdict must be `SAFE TO LAND` |
| `gh pr merge` before every check passed, or `--admin` | Wait for every check; never bypass protections |
