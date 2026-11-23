---
name: review
description: Use when the user asks for a mash review, a code review or a self-review of their changes, before opening a pull request or sharing a branch, or when deciding which review standards a change needs
---

# Review a change against the project's standards

This skill changes no code. It never fixes, commits, stashes, pushes, opens a pull request or comments. When the user also asked for fixes, the session makes them after the summary, with the builder skill each finding's standard names. Details for each step, and common mistakes: `reference.md` next to this file.

**Plan mode:** do steps 1–4 by reading only, then write the review plan (range, intent, standards and why, reviewers and models, checks to run) and stop. Run no check, start no reviewer, write no file.

**User present** means a person can answer now. Auto mode, `claude -p` and background sessions have none.

## Steps

1. **Range.** Base: `git merge-base <default branch> HEAD` (`origin/HEAD`, else `origin/main` or `origin/master`, else local `main` or `master`, else ask), or the base the user names. Note the commit id (`git rev-parse HEAD`) and the untracked files. Changes outside `.mash-review/` and `.claude/worktrees/` that are uncommitted or untracked: ask _review everything, commit first, or only the commits?_; with no user present, use everything and say so in the report. Everything is **working-tree mode** (its section in `reference.md`).
2. **Intent.** From the commit messages (`git log <base>..HEAD`), the PR description, or the user. One commit: put its message in the intent.
3. **A fixed escape?** If the change fixes a bug that a review passed, run the `record-escape` skill for it.
4. **Standards.** List the skills whose `description` covers what this diff does ("Selecting standards" in the reference). Add every standard the project's `CLAUDE.md` or `AGENTS.md` requires for this change. Group them into reviewers and give each group a model ("Grouping"). With none selected: one reviewer with the general checklist only.
5. **Checks, once.** Run the test, lint and format commands that `CLAUDE.md` or `AGENTS.md` names. With none, propose commands from the project files and run only those the user confirms ("Check commands"). Nothing to run: tell reviewers "no automated checks ran" and mark the summary **Unchecked**. A red check: ask "stop here, or review anyway?". Stop, or no user present: report the failures and start no reviewer. Review anyway: give the red results and mark **Checks red**.
6. **Start every reviewer in one message.** `subagent_type: mash-review:reviewer`, `model` from step 4, and the prompt in "Reviewer prompt". A reviewer that errors or gives no verdict is started again once; a second failure is **no verdict**, and the review is `NOT SAFE`. Where there are no subagents, do each review in the main conversation with the instructions of `../../agents/reviewer.md` from this skill's folder.
7. **Escapes.** Each Pre-existing finding with `escape: yes`: run `record-escape`.
8. **Summary, in the terminal** ("Summary" in the reference): each reviewer's verdict and standards; findings with their standard; the checks line; Pre-existing findings; escapes recorded, waiting, or to confirm; the offers; the migration hint. Then stop.

A **re-review** on request goes only to the reviewers that found something ("Re-review" in the reference). There is no round limit; a caller that loops sets its own.
