# review-changes reference

## General-purpose reviewer prompt

Only when `route` printed `general-purpose` (a project config that still names it), put this first in its prompt: "read-only: do not edit files; group findings as Critical / Important / Minor / Pre-existing and end with exactly one line, judged on this change as it stands: `SAFE TO LAND` only when there are no Critical and no Important findings (Minor findings are suggestions and do not block); any Critical or Important finding gives `NOT SAFE: <why>`, even when the author says it will be fixed later".

## Fix rounds

1. Note `git rev-parse HEAD`.
2. Fix in a new commit, rerun the checks.
3. Send `git diff <noted head> HEAD` to every reviewer that `route <noted head>..HEAD --models` prints, plus every reviewer that found something; not the whole change again. When the default branch was merged in since the noted head, use `git log -p --first-parent --no-merges <noted head>..HEAD` plus `git show` of each merge that `git log --first-parent --merges <noted head>..HEAD` lists, so the base's commits don't pose as the fix.
4. Start each reviewer on the model step 1 gave it (a reviewer new in this round: run `route <range> --models` again). Never take models from the `..` range: it sees only the fix's commits, so a model rule for new features wouldn't hold.

## Recording escapes

An escape is a bug in code a review passed, found later by anyone: a person, CI or a later reviewer. The ledger (`docs/review-escapes.md`) holds one line per bug, keyed by its issue link. Pros of the issue link as the key: every path (a fix, a Pre-existing finding, a bug a person found) has one, and re-running a step cannot count a bug twice. Con: a bug with no issue has to get one first; the user files it on their host and gives you the link.

Run `bash <this skill's base directory>/../add-reviewer/escape-add.sh <repo-root> <area-directory> <class> <issue link>`. The area is the directory a route claims (`src/payments`), never a file.

- **Step 0, a fix:** record the issue the fix closes; ask the user for the link.
- **Step 4, a Pre-existing finding:** reviewers mark each one `escape: yes` (a behaviour bug with a failure scenario: a wrong result, data lost, a guard bypassed, in code an earlier review passed) or `escape: no` (drift, hygiene, testability, perf, and code no review covered: it predates any review, a direct push, vendored code). A finding in a change still under review is a finding for that change, not an escape. Record each `escape: yes` once the user gives the issue link. A wrong `yes` costs one ledger line, and the issue it links is visible.
- **A bug a person or CI found:** record the issue for it.

A link the ledger already holds prints "already recorded" and exits 0, so a repeat is safe. When the area is at or over the threshold (default 2) after the new entry, the script also prints that area's report line, ending "-> add a reviewer for <area> (add-reviewer skill)". Tell the user, who decides whether to run add-reviewer. Commit the ledger change with the fix (a ledger the project gitignores is updated but not committed). The link is normalised: a GitHub issue or PR URL, `owner/repo#N` and `#N` (owner and repo from the origin remote) all become `https://github.com/<owner>/<repo>/issues/N`; any other http(s) link is kept as given; `#N` with no GitHub origin is refused.

An existing ledger keeps its old header, and old entries keyed by PR links stay as they are. The report counts each distinct link once per area.

## Common mistakes

| Mistake | Instead |
|---|---|
| Picking reviewers from the file names you remember | Run `route`; docs, scripts and `.claude/` may have reviewers too |
| Reading a non-zero exit as "no reviewers needed" | Fix the range or config and run it again |
| Skipping `review-routing:change-reviewer` because "it's a small change" | Every agent the script prints is dispatched |
| Letting reviewers run the suite and linters | Run them once; pass the results in each prompt |
| Dispatching reviewers while a test, linter or formatter is red | Fix the deterministic failures first |
| Running a check command `find-checks.sh` listed without asking | It lists candidates; the user confirms |
| A clean verdict reported with no checks having run | Say **Unchecked** in the summary |
| A reviewer flags formatting, style or a convention and the fix stops there | Automate it (test, lint rule, formatter, hook) |
| Re-reviewing the whole change after a small fix | Send the fix's diff to the reviewers step 4 names |
| Starting a fix-round reviewer without a model | Use the model step 1 gave it |
| Fixing an old bug a reviewer spotted inside this change | List it as Pre-existing; one concern per change |
| Counting a reviewer that crashed or gave no verdict as safe | Dispatch it again |
| Calling the branch ready while a reviewer said `NOT SAFE` | Every last verdict must be `SAFE TO LAND` |
