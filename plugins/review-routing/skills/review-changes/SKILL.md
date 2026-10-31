---
name: review-changes
description: Use when you are about to open a pull request or share a branch, when asked to review or self-review your changes, or when deciding which reviewer agents a change needs
---

# Review your changes before opening a PR

Reviews committed work with the reviewer agents the project's routing (`.claude/reviewers.toml`) names for it. It needs only git and writes nothing to a PR. Below, `route` means `python3 <this skill's base directory>/reviewers-for-change.py`, run from the repository.

**Reviewers judge; tools enforce.** Whatever a tool can decide belongs in automation, not in a reviewer's attention.

## Steps

0. **Does this change fix a bug that a review passed?** Ask for its issue link and record it ("Recording escapes" in `<this skill's base directory>/reference.md`).
1. **Range and reviewers.** Review `<default branch>...HEAD` (`origin/HEAD`, else `main` or `master`, else ask) unless the user names another base. Uncommitted changes: ask the user to commit first. `route <range> --models` prints `agent<TAB>model` lines. A non-zero exit means the range or config is wrong, never "no reviewers". Dispatch every agent printed, with the printed name as `subagent_type` and the printed `model`, unless it is `-` (the agent's default; for `general-purpose` pass `sonnet`). With no `.claude/reviewers.toml` only `review-routing:change-reviewer` is printed: say that the add-reviewer skill sets up routing. When the change touches `.claude/reviewers.toml` or `.claude/agents/`, also run `route --check`.
2. **Checks first, once, as a gate.** Use the test, lint and format commands that CLAUDE.md or AGENTS.md names. If none: `bash <this skill's base directory>/find-checks.sh <repo-root>` lists candidates (if it fails, treat the list as empty); propose them, run only what the user confirms, then offer a CLAUDE.md line naming them. If nothing exists, review anyway: tell reviewers "no automated checks ran", pair every mechanical finding with the tool that would catch it, and report **Unchecked: no tests or linters configured**. Fix any failure before step 3.
3. **Dispatch all reviewers in one message.** Each prompt holds: the range to review (`git diff <range>`), what the change is for in one or two sentences, the check results, and anything the agent's description says the caller must name. For `general-purpose`, first add "General-purpose reviewer prompt" from the reference. A reviewer that errors or gives no verdict is dispatched again, never counted as safe.
4. **Triage every finding.**
   - Mechanical: fix it and add (or propose) the check that now covers it. With mash-workbench, record it with `scout`.
   - Introduced by this change: fix in a new commit (never an amend), rerun the checks, then send the fix round to the reviewers ("Fix rounds" in the reference). After two rounds still `NOT SAFE`, stop and report the open findings.
   - A finding you think is wrong: answer it with evidence in the next round's prompt to that reviewer; its verdict decides.
   - Pre-existing: list it for the user; file nothing. Record each `escape: yes` once the user gives an issue link.
5. **Summary, in the terminal only:** each reviewer's last verdict, Critical / Important / Minor counts and fix rounds; the checks that ran or the Unchecked line; open Minor suggestions; Pre-existing findings. Say "ready to open your PR" only when every last verdict is `SAFE TO LAND`; otherwise list what is open. Never push, open or comment on a PR, or merge.
