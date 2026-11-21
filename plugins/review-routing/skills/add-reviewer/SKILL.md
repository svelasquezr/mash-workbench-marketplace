---
name: add-reviewer
description: Use when the bugs a review passed in one area reached the escape threshold (default 3), when a bug is found in code that review had passed, when the user names an area of the project that is expensive to get wrong, or when a project starts routing its reviews to specialist reviewer agents
---

# Add a specialist reviewer

A specialist reviewer earns its place. Add one when:

- **an area reached the escape threshold (default 3)**: its checklist is built from the bugs a review passed there. The count comes from the project's escapes folder, not memory: `bash <this skill's base directory>/escapes-report.sh <repo-root>` names each area at the threshold (an escape is a bug in code a review passed, found later by anyone: a person, CI or a later reviewer; one file per bug, written by `bash <this skill's base directory>/escape-add.sh`). To record one, set the folder up, or migrate an old ledger, follow the escapes sections of `<this skill's base directory>/../review-changes/reference.md`; the area is the directory a route claims, never a file; or
- **the user names an area where one mistake is expensive** (money, auth and security, data migrations, a public API contract, infrastructure). This is usually how the first specialist starts.

Don't add one for a rule a test, linter, formatter, type checker or hook can enforce: make it that instead (hook > script/test > skill > agent), because a tool is exact, free to run and never tired, and a reviewer is none of these. Style, formatting, naming, import order, a banned call, a required file or header: automate. A reviewer's checklist keeps only what needs judgment. Don't add one for an area a general review already covers well either. One area per agent.

Below, `route` means `bash <this skill's base directory>/../../scripts/python.sh <this skill's base directory>/../review-changes/reviewers-for-change.py`, run from the repository. Exit 3 means no Python 3.11 was found: stop, show the user its message, and do not write routing that `route --check` cannot test.

## Reference

`<this skill's base directory>/reference.md` holds the config keys, the model sizing policy, the parts of the agent file to keep verbatim, and how to manage a growing set of reviewers. Read its "Writing the agent" before step 2, "Routing details" before step 3 and "Checking" before step 5.

## Steps

1. **Gather the evidence:** the escape files ("Escape evidence" in the reference), PRs or incidents behind the request, the area's paths, the invariants that must hold. Read the code; ask the user only what it can't tell you, with a recommendation for each question.
2. **Write the agent:** copy `<this skill's base directory>/reviewer-template.md` to `.claude/agents/<area>-reviewer.md` and replace every `<...>`.
   - Model and effort: `model: sonnet`, `effort: high`; pin `opus` (or `fable`) where one miss loses money or data, with the reason in a YAML comment; never `haiku`. Keep the template's read-only tools, judge-only paragraph, output format, verdict line and claims-about-the-system checklist item verbatim. Why and how: "Writing the agent" in `<this skill's base directory>/reference.md`.
   - The checklist is paths, invariants and linked bugs; the `description` holds no paths. Drop items a tool can check.
3. **Route it:** create `.claude/reviewers.toml` from `<this skill's base directory>/reviewers.example.toml` if the project has none (replace the example routes and expectations). Then add:
   - `[[routes]]` for the area's paths;
   - once per project, a `[[mirrors]]` entry so a test counts as the code it tests;
   - `[[changed_lines]]` when a line in a shared file belongs to the area.
     Details: "Routing details" in the reference.
4. **Add routing test cases:** for each new route, an `[[expect]]` for a path it must claim, one for a near miss it must not (for `^src/payments/`, `src/app/payments_page.py`), and one for a test file through the mirror.
5. **Check:** `route --check` until it passes; preview with `route --paths <file>... --explain`. Never add a pattern just to quiet `--check` for a path that belongs to a specialist; list in `allow_default` only the paths a general review is enough for, each with a comment. What it fails on: "Checking" in the reference.
6. **CLAUDE.md:** if it isn't there yet, add one rule: "Review every change with the agents `.claude/reviewers.toml` routes it to (the review-changes skill); pass them the test and lint results."
7. **Ship** the agent, the config and its test cases as one change, reviewed with the review-changes skill. Once it lands, move the area's escape files to `processed/` ("Escape evidence").
