# review reference

The design, with diagrams, is `docs/specs/mash-review.md` in the marketplace repository.

## Selecting standards

A review standard is a skill whose `description` says when it applies to a review:

- a project skill `review-<topic>/SKILL.md`: a companion of a builder skill, or a standalone standard for a domain such as payments or auth. Look in `.claude/skills/`, `.github/skills/` and `.agents/skills/`;
- a builder skill with a "Review checklist" section; its description says "Use when writing or reviewing …".

Read the `git diff --stat <base>...HEAD` (or `git diff --stat <base>` in working-tree mode) and enough of the diff to know what kinds of code it changes. Match that against the descriptions of the skills you can see. A folder is a hint, never the rule: one folder can hold components, services and domain code. Write down each selected standard with one line on why.

Then read the project's instruction files (`CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`), and the nested ones in the touched folders, for rules that require a standard, for example "A change under `src/payments/` always gets the `review-payments` standard". Apply each such rule, and name it in the summary. This is how a project makes selection deterministic; the plugin has no config of its own.

**A change that edits its own rules.** When the diff changes a selected standard, a builder skill it cites, or an instruction file, also apply the version at the base (`git show <base>:<path>`): select and require standards from both versions, tell the reviewer that the standard changed in this diff, and name the change in the summary. A change must not weaken the rules that review it.

A builder skill with no "Review checklist" section is not a standard. When the change is mostly that kind of code, add an offer to the summary: "Create a review standard for <kind> (add-standard)?".

## Grouping

- One reviewer for each group of standards that fit together in one review, by size of the diff and by model. A small change: one reviewer with every standard. A large change with unrelated standards (UI and database): one reviewer for each.
- Read the body of each selected standard for a `Model:` line (in a builder skill, inside its "Review checklist" section). A standard's model is the one on that line, else `opus`. The model of a group is the strongest of its standards' models (`fable` over `opus` over `sonnet`), so a group runs on `sonnet` only when every standard in it says `Model: sonnet`. A reviewer with no standard runs on `opus`.
- A model the user names in the request ("review with sonnet") wins for every reviewer; name it in the summary.
- Never `haiku`, even on request: use `sonnet` and say so in the summary. A blind test had a Haiku reviewer accept a false claim and answer `SAFE TO LAND`.
- Every reviewer also applies the general checklist of the agent.

## Working-tree mode

The change is the base against the working tree: the reviewer runs `git diff --no-ext-diff --function-context <base> -- ':(top)' ':(top,exclude).mash-review' ':(top,exclude).claude/worktrees'`. List the untracked files for the prompt with `git status --porcelain --untracked-files=all`, leaving out `.mash-review/` and `.claude/worktrees/`, as paths from the top folder of the repository (`git rev-parse --show-toplevel`). Write no snapshot, stash or temporary file: with no user present, Claude Code refuses commands that write (`git stash create`, a redirect to a file), and read-only git runs.

## Check commands

1. Use the commands that the instruction files name for tests, lint, types and format.
2. With none: read `package.json` (`scripts`), `Makefile`, `justfile`, `pyproject.toml`, `tox.ini`, `Cargo.toml`, `go.mod`, `.pre-commit-config.yaml` and the CI workflow files, and propose the commands they define. Run only the ones the user confirms. With no user present: run none, and mark **Unchecked**.
3. After they run, offer a line in the instruction file the project uses (`CLAUDE.md` for Claude Code, `AGENTS.md` or `.github/copilot-instructions.md` for Copilot CLI) that names them ("Checks: `npm test`, `npm run lint`"). Write it only on a yes.
4. Run each command once, before the reviewers. Give the results to every reviewer in one line ("suite: 412 passed; lint and types clean").

## Reviewer prompt

In this order:

1. The range `<base>...HEAD`; or "working-tree mode, base `<base>`: run `git diff --no-ext-diff --function-context <base> -- ':(top)' ':(top,exclude).mash-review' ':(top,exclude).claude/worktrees'`"; or, for a re-review, the diff command from "Re-review".
2. The base, and "two or more commits: read `git log <base>..HEAD`" when that is so.
3. The intent, in one to three sentences.
4. The check results, "no automated checks ran", or **Checks red** with the failures.
5. The standards to apply, each by skill name and `SKILL.md` path, with why it was selected, and which of them the diff itself changes; or "no standard selected: general checklist only".
6. In working-tree mode, the untracked files to read.
7. For a re-review, the reviewer's earlier findings.

Do not paste the diff: each reviewer runs `git diff` itself, and pasted text costs output tokens once for each reviewer.

## Re-review

Only on request, after a fix. Start only the reviewers that found something, with the same standards, the same models, and their earlier findings.

- The fix is committed: the diff is `git diff --no-ext-diff --function-context <noted commit id> HEAD -- ':(top)' ':(top,exclude).mash-review' ':(top,exclude).claude/worktrees'`.
- The fix is not committed: `git diff --no-ext-diff --function-context <noted commit id> -- ':(top)' ':(top,exclude).mash-review' ':(top,exclude).claude/worktrees'`, plus untracked files: in working-tree mode every untracked file again (with the same exclusions), because the first change can hold untracked files the fix edited; in "only the commits" mode only the ones that are not on the list noted in step 1.

The diff can hold more than the fix: the first change in working-tree mode, the first change committed together with the fix, or uncommitted work the user left out in "only the commits" mode. Tell the reviewer to check its earlier findings first, and to report only on the fix and those findings.

A finding you think is wrong: answer it with evidence in that reviewer's re-review prompt; its verdict decides.

## Summary

In the terminal only. With no user present, the same content goes in the final report.

1. The mode: the range, or working-tree mode (and why, when no user was present); the base and the noted commit id, so a later session can build the re-review diff. Each reviewer: its verdict, its standards, its model, and the changed files it did not open (secrets files). A reviewer with **no verdict** makes the result `NOT SAFE`.
2. The findings: Critical, Important and Minor, each with `path:line` and its standard.
3. The checks line: the results, **Unchecked**, or **Checks red**. In "only the commits" mode with uncommitted changes, add that the checks ran on the working tree.
4. Pre-existing findings, ready to file as issues. File nothing.
5. Escapes: the ones recorded and where; the waiting escape files in `<main worktree>/.mash-review/escapes/` by topic (count the `.md` files, not `processed/`); with no user present, the block **Escapes to record (confirm where)** that `record-escape` gave.
6. Offers, each done only on a yes: a review standard (add-standard) for a kind of code with no standard; an instruction-file line for the check commands. Topics with three or more waiting files are in the escapes list of item 5 as a reminder; the offer itself comes from `record-escape` when a write brings a topic to exactly 3 or 5.
7. Migration hint: when `.claude/reviewers.toml` exists in the current worktree, or untracked old escape files exist in `.claude/mash-workbench/escapes/` of the main worktree, "This project still has review-routing files. Run `/mash-review:migrate`."
8. The fix path: when the user asked for fixes, say which builder skill each finding's standard names.

## Common mistakes

| Mistake                                                | Instead                                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Fixing findings because the review found them          | Stop at the summary; fix only when the user asked, with the standard's builder skill |
| Pasting the diff into the reviewer prompt              | Give the range; the reviewer runs `git diff`                                         |
| Selecting standards by folder                          | Select by what the diff does; a folder can hold several kinds of code                |
| Skipping review because no standard matched            | Start one reviewer with the general checklist                                        |
| Writing a standard or an instruction-file line unasked | Offer it in the summary                                                              |
