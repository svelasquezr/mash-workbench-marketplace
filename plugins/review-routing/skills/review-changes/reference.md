# review-pr reference

## Recording escapes

An escape is a bug in code a review passed, found later by anyone: a person, CI or a later reviewer. The ledger (`docs/review-escapes.md`) holds one line per bug, keyed by its issue link. Pros of the issue link as the key: every path (a fix PR, a Pre-existing finding, a bug a person found) has one, and re-running a step cannot count a bug twice. Con: a bug with no issue has to get one first.

Run `bash <this skill's base directory>/../add-reviewer/escape-add.sh <repo-root> <area-directory> <class> <issue link>`. The area is the directory a route claims (`src/payments`), never a file.

- **Step 0, a fix PR:** record the issue the fix closes. When the PR has no `Closes #N`, file the issue first.
- **Step 4, a Pre-existing finding:** reviewers mark each one `escape: yes` (a behaviour bug with a failure scenario: a wrong result, data lost, a guard bypassed, in code an earlier review passed: merged to main, or in another PR whose review ended `SAFE TO LAND`, still open or merged) or `escape: no` (drift, hygiene, testability, perf, and code no review covered: it predates any review, a direct push, vendored code). A finding in a PR still under review is a finding for that PR, not an escape. Right after `gh issue create`, record each `escape: yes` by the new issue's link. A wrong `yes` costs one ledger line, and the issue it links is visible.
- **Step 4, a bug a person or CI found:** record the issue for it.

A link the ledger already holds prints "already recorded" and exits 0, so a repeat is safe. When the area is at or over the threshold (default 2) after the new entry, the script also prints that area's report line, ending "-> add a reviewer for <area> (add-reviewer skill)". Put that line in the PR body beside the issue links, so the owner sees it in GitHub even when every session is headless, and decides whether to run add-reviewer. Commit the ledger change in the PR. A ledger-only commit made during triage needs no new review round, and landing uses the new head. In a fork, `#N` resolves through origin, so pass the full issue URL `gh issue create` printed. The link is normalised: an issue or PR URL, `owner/repo#N` and `#N` (owner and repo from the origin remote) all become `https://github.com/<owner>/<repo>/issues/N`; `#N` with no GitHub origin is refused.

An existing ledger keeps its old header, and old entries keyed by PR links stay as they are. The report counts each distinct link once per area.

## Review round comments

Reviewer agents report only to the session that dispatched them, so without these comments the user can't read the findings on GitHub. Post one comment per round (round 1, then each fix round), after that round's triage, so it can say what happened to each finding. Write the body to a file outside the repository and post it with `gh pr comment N --body-file <file>`.

The body:

1. A heading `Review round <N>`, and for a fix round the range it reviewed (`<noted head>..<new head>`).
2. A table with one row per reviewer: agent, model, verdict, then Critical / Important / Minor counts.
3. One line per finding: reviewer, severity, a short title, and its status:
   - `fixed in <sha>`;
   - `answered: <one line>`: a finding you think is wrong; the next round's comment reports that reviewer's verdict on it; with no round following, it stays `answered`;
   - `issue #N`: Pre-existing;
   - `open: <reason>`: not acted on, such as a Minor suggestion left as is, or a Critical or Important finding still open when the session stops after two fix rounds.
4. Each reviewer's full report in a collapsed block, so the PR page stays short. GitHub renders markdown inside it only with a blank line after `</summary>` and before `</details>`:

   ```
   <details><summary>agent-name: SAFE TO LAND</summary>

   …the report, unchanged…

   </details>
   ```

GitHub refuses a comment over 65,536 characters. Check the body with `wc -c <file>`. Past 60,000, post the heading, table and finding lines in one comment, then the reports in more comments headed `Review round <N> (part 2)` and so on, each under 60,000.

A `<sha>` or range in a posted comment stops resolving on GitHub once that commit is amended or rebased away. Make each fix round a new commit, never an amend or a rebase (the squash merge gives main one commit), and take main in with a merge.

Rounds run before the PR exists (a project that reviews the unpushed branch; this skill has no pre-PR mode yet, so its push, PR and comment steps wait for the PR): keep each round's body, then post them in round order right after the PR opens.

The closing "Review verdicts" comment (step 5) stays as it is: tools read its `VERDICT:` line.
