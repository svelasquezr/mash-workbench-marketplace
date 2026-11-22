# review-changes reference

## General-purpose reviewer prompt

Only when `route` printed `general-purpose` (a project config that still names it), put this first in its prompt: "read-only: do not edit files; group findings as Critical / Important / Minor / Pre-existing and end with exactly one line, judged on this change as it stands: `SAFE TO LAND` only when there are no Critical and no Important findings (Minor findings are suggestions and do not block); any Critical or Important finding gives `NOT SAFE: <why>`, even when the author says it will be fixed later".

## Fix rounds

1. Note `git rev-parse HEAD`.
2. Fix in a new commit, rerun the checks.
3. Send `git diff <noted head> HEAD` to every reviewer that `route <noted head>..HEAD` prints, plus every reviewer that found something; not the whole change again. When the default branch (and only it) was merged in since the noted head, use `git log -p --first-parent --no-merges <noted head>..HEAD` plus `git show` of each merge that `git log --first-parent --merges <noted head>..HEAD` lists, so the base's commits don't pose as the fix. When the merge took in commits from the branch's own remote (`git merge origin/<feature>`), those sit on the merge's second parent and `--first-parent` hides them: send the plain `git diff <noted head> HEAD`.
4. Start each reviewer on the model SKILL.md step 1 gave it (a reviewer new in this round: run `route <range> --models` again). Never take models from the `..` range: it sees only the fix's commits, so a model rule for new features wouldn't hold.

## No Python

`route` exits 3 when it finds no Python 3.11 or newer (`python3`, `python` and `py -3` were tried; on Windows the Microsoft Store alias, which prints "Python was not found", does not count). Then:

1. Show the user the message `route` printed: it says how to install Python or set `MASH_PYTHON`.
2. Do not guess the routing. Dispatch only `review-routing:change-reviewer` on `sonnet`, and continue with step 2. Skip `route --check` too (it needs Python as well), and say so in the summary.
3. In the step 5 summary, add the line **Routing skipped: no Python 3.11 found (set MASH_PYTHON or install Python 3.11+)**. If `.claude/reviewers.toml` exists, list the agents it names (the `reviewers` values), so the user can ask for any of them by name.

## Review log and escape lines

Step 5, when every reviewer's last verdict is `SAFE TO LAND`:

1. **Log the range.** `bash <this skill's base directory>/review-log.sh add <repo-root> <base> <head>`. For a `<default>...HEAD` range, `<base>` is `git merge-base <default> HEAD`. When the user commits after the review, you run `add` after that commit, with `<base>` and the new `HEAD`. The line goes to `reviews.log` in the main worktree's `.claude/mash-workbench/` folder, which the script lists in the repository's `info/exclude`: nothing reaches a commit or a pull request. It records the range's patch-ids too, so a later squash or rebase merge still matches. The record-escape skill asks `review-log.sh reviewed <repo-root> <commit>` whether a commit passed a review (exit 0 yes, anything else no answer in the log: a squash merge that needed conflict fixes has another diff, so the skill then asks the user). `add` refuses a base that is not an ancestor of the head and a range with no changes (exit 2). Not logged on `NOT SAFE`; a failure to log does not block the summary: say so in one line.
2. **Escape lines.** Run `bash <this skill's base directory>/../add-reviewer/escapes-report.sh <repo-root>` and add one line to the summary for each area it marks `-> add a reviewer for <area>` (threshold: default 3, or the `escapes.threshold` setting; a declined area is not marked). Ask the user, once per area: "<area> has N escapes that a review passed. Add a specialist reviewer for it?" Yes: run the add-reviewer skill. No: `bash <this skill's base directory>/../../scripts/mash-settings.sh set <repo-root> declined.<area> <YYYY-MM-DD>:<N> --local`; the report asks again at N + 2.
3. **Uncommitted escape files.** With committed escapes, count the files that wait (`git -C <main worktree> status --porcelain --untracked-files=all -- <escapes folder>`, leaving out `README.md`) and add "N escape files wait uncommitted in <folder>" when N is above 0. The user commits them from the main worktree. No skill commits them.

## Recording escapes

An escape is a bug in code a review passed, found later by anyone: a person, CI or a later reviewer. Each escape is one file in the project's escapes folder (by default `.claude/mash-workbench/escapes/` in the main worktree, the folder where the repository was cloned; `bash <this skill's base directory>/../add-reviewer/escapes-path.sh <repo-root>` prints it). The file describes the bug, so add-reviewer needs no git host, and separate files never conflict in a merge.

1. **Is it a repeat?** `bash <this skill's base directory>/../add-reviewer/escape-add.sh --list <repo-root> <area>` prints that area's escapes, newest first, one line each. If one is the same bug, say so and record nothing.
2. **The body.** Write it in ASD-STE100: the conditions, then the incorrect result, then the expected result. It is one paragraph on one line, with the sentences separated by spaces; `--list` shows its first line as the summary.
3. **Record.** `bash <this skill's base directory>/../add-reviewer/escape-add.sh <repo-root> <area-directory> <class> <slug> --body "<the body text>" [--source <link>]`. The body is the text itself, in double quotes; write no file for it. The script opens no file that an argument names (`--body-file` is gone), so a rule that lets it run with no prompt cannot be used to copy a file into the escapes folder. Keep `$`, backticks and double quotes out of the body: Claude Code asks for approval when quoted text holds a command substitution. The area is the directory a route claims (`src/payments`), never a file. The class and the slug are lowercase words joined by `-` (`wrong-result`, `discount-tax`). Add `--source` when there is a link: a review comment, an issue or a pull request. For several escapes at once, `--batch - <repo-root>` reads blocks from standard input, in the file format below, each with a `slug:` line, separated by a line `---8<---`: send them in a here-document with a quoted delimiter (`<<'BATCH'`), or run the single command once for each escape.

When to record:

- **Step 0, a fix:** the bug the fix closes; the source is its issue or the review comment that found it, when there is one.
- **Step 4, a Pre-existing finding:** reviewers mark each one `escape: yes` (a behaviour bug with a failure scenario: a wrong result, data lost, a guard bypassed, in code an earlier review passed) or `escape: no` (drift, hygiene, testability, perf, and code no review covered: it predates any review, a direct push, vendored code). A finding in a change still under review is a finding for that change, not an escape. Record each `escape: yes`. A wrong `yes` costs one file, which the user can delete.
- **A bug a person or CI found:** record it.

What the script answers:

- "the escapes ledger is off" (exit 0): say nothing more and continue.
- Exit 3, "no escapes folder chosen yet": follow "Setting up escapes" below, then record again.
- Exit 3, "old ledger format": follow "Migrating an old ledger" below.
- Exit 6: refused, and the message says why; show the user. A folder in a linked worktree, a temporary folder, the git directory or a folder another repository owns: ask for another folder. "the committed settings file puts the escapes folder outside the repository": a committed file may not choose that; ask the user, and only on a yes run the `mash-settings.sh set ... --local` command the message gives. "a symbolic link": the home folder, the escapes folder or its `README.md` is a link (a repository can commit one); record nothing until the user has looked at it. "not the installed version": the plugin was updated during this session and this copy is an old one; tell the user to start a new session, and that the allow rules for the old folder must go (step 3 of "Setting up escapes").
- Claude Code refuses the command ("requires approval") and no user is there to approve it, as in a `claude -p` session: the allow rules are missing or name another plugin version. Do not try another spelling or a wrapper such as `bash -c`. Put each escape in your final report (area, class, slug, body, source), and say that a session with a user must record them and run step 3 of "Setting up escapes" again.
- "already recorded: <file>" (exit 0): an escape with the same area and the same source is already in the folder, so a repeat is safe. The same source in another area is another escape, as the report counts it.
- A line ending "-> add a reviewer for <area> (add-reviewer skill)": the area reached the threshold (default 3, the `escapes.threshold` setting). Ask the user: "<area> has N escapes that a review passed. Add a specialist reviewer for it?" Yes: run the add-reviewer skill. No: save the decline with `bash <this skill's base directory>/../../scripts/mash-settings.sh set <repo-root> declined.<area> <YYYY-MM-DD>:<N> --local`; the report asks again at N + 2.

The file goes to the escapes folder in the main worktree, also when you work in a linked worktree. No skill commits escape files. With committed escapes, tell the user "N escape files wait uncommitted in <folder>" (count them with `git -C <main worktree> status --porcelain --untracked-files=all -- <folder>`, leaving out `README.md`); the user commits them from the main worktree, never on the fix branch.

The source link is normalised: for a `github.com` link, `www.`, a `?query`, a trailing `/` and the fragment are dropped, but a review comment keeps `#discussion_r<id>` (the files view's `#r<id>` becomes that), a `#note_<id>` stays, and on a pull request `#issuecomment-<id>` and `#pullrequestreview-<id>` stay; `/pull/N` stays a pull request, and its `/files`, `/changes`, `/commits` or `/checks` page is the pull request; `owner/repo#N` and `#N` (owner and repo from the origin remote) become `https://github.com/<owner>/<repo>/issues/N`. Any other http(s) link only loses a trailing `/`. `#N` with no GitHub origin is refused.

## Setting up escapes

When `escape-add.sh` exits 3 with "no escapes folder chosen yet", nothing has been written. Ask, then set it up:

1. **Where.** Ask the user, in one question, where to keep escapes, with a recommendation: `.claude/mash-workbench/escapes` committed (recommended: the whole team's misses add up), the same folder excluded (only this clone), another folder, or none (`off`). Check a path first with the `check-escapes-path` command the script printed: it says what the choice means, or refuses (exit 6) a linked worktree, a temporary folder, the git directory, or a folder another repository owns. For an excluded folder inside the repo, add it to `<git common dir>/info/exclude` (`git rev-parse --git-common-dir` names the dir).
2. **Save the answer.** Run the `mash-settings.sh set` command the script printed: `--team` for committed escapes (the `settings` file is committed with them), `--local` for excluded escapes, a folder outside the repo, or `off`. Exit 1 means another writer holds the settings lock: run the same command again. If it persists, the message names the lock folder (`.settings.lock`): check that no other session is writing, then remove that folder and run the command again.
3. **Offer write access**, whatever the answer was: with it, a session with no user (`claude -p` in a new worktree) records without a prompt. Run `bash <this skill's base directory>/permission-rules.sh <repo-root>`. It only prints: the `file:` to edit (`.claude/settings.local.json` in the main worktree; create it when it is missing), a `present:`, `add:` or `remove:` line for each rule, and `note:` lines. When it prints `remove:` lines, they come first and they are not optional: show them to the user, say why (below), delete them from `permissions.allow`, and run the script again. It prints no `add:` line while a `remove:` line is there. Then show the user the `add:` rules and add them to `permissions.allow` of that file only on a yes. Edit the file with your own edit tool, so Claude Code asks the user to approve the write too; no script edits it. A rule with double quotes in it needs them escaped in the JSON (`\"`). The script reads which list a rule is in: `present:` and `remove:` are about `allow` lists only, and a note names a current rule that is also in a `deny` or `ask` list (that list wins). It reads only the main worktree's file and the current linked worktree's: tell the user to remove the same old rules from any other settings file they copied them to (another worktree's `.claude/settings.local.json`, `.claude/settings.json`, `~/.claude/settings.json`). Exit 6 means no rule is safe for this copy of the plugin (the message says why): add none, and let the user approve each command. Exit 2 or 5 means there is no git repository or no main worktree to hold the file: skip this step and say so.

   A rule looks like `Bash(bash <plugin folder>/skills/add-reviewer/escape-add.sh *)`. Why this shape: Claude Code compares a rule with the command text letter for letter, and `*` matches any text, spaces too. So a rule is safe only when the script path is exact and the one wildcard is at the end, for the arguments. A wildcard before the script path allows any command that mentions the script's name, such as `bash -c '<anything>' <the name>`. The rules that this section offered in review-routing 0.4.0 to 0.5.0 began with `bash *`: they are the `remove:` lines, and they must go, also from any other settings file the user copied them to. There is one rule for each spelling a skill writes (`.../skills/record-escape/../add-reviewer/escape-add.sh` is another text than `.../skills/add-reviewer/escape-add.sh`), and only for `escape-add.sh` and `review-log.sh`. The steps that need the user's answer first (`escape-migrate.sh`, `mash-settings.sh set`) get no rule. What a rule still allows: any arguments to that one script. The scripts open no file that an argument names, but `<repo-root>` is an argument, so the rule also approves a record in another repository on the machine that has an escapes folder chosen.

   For a rule to match, write the command as the skill gives it: `bash`, then the script path with this skill's base directory written out (no variable, no `cd` before it, no other spelling of the path; double quotes only when the path has a space), then the arguments. Join nothing to it (`&&`, `;`, a pipe, an output redirect) and put no `$( )` in it: Claude Code then asks for approval, whatever the rule. The one exception is the here-document with a quoted delimiter that `--batch -` reads.

   After a plugin update the path has a new version folder, so the old rules no longer match the new scripts. That is on purpose: a new version's scripts run with no prompt only after the user allowed them again. But the old rules still match the old version's scripts, which Claude Code keeps in its plugin cache, so they must go: run this step again after every update; it prints the old rules as `remove:`, and after they are gone the new ones as `add:`. From 0.6.0 on, `escape-add.sh` and `review-log.sh` also refuse to run from a copy that is not the installed version (exit 6); the scripts of 0.5.1 and earlier do not, so for them removing the rules is the only protection.

   Why that file: git does not track it, so Claude Code applies it in every new worktree with no trust step. The committed `.claude/settings.json` is ignored until the user accepts the workspace-trust dialog, and `~/.claude/settings.json` would allow these scripts in every project. The rules use `Bash`, because an `Edit` rule cannot open `.claude/`. A sandbox user also needs the sandbox settings the README names. Under `claude --plugin-dir <folder>` the rules name that folder; when it, or a symbolic link on the path to it, is inside a worktree of the repository, the script offers none. In a tool other than Claude Code, skip this step.

4. Record the escape again.

## Migrating an old ledger

When `escape-add.sh` exits 3 with "old ledger format at <file>", or the report or `escapes-path.sh` says "run escape-migrate.sh", the project still keeps escapes in the old one-line-per-escape file (`docs/mash/review-escapes.md`, `docs/review-escapes.md`, or a file the `escapes` setting names). Nothing is recorded until it is migrated.

1. **Explain and ask.** The new format keeps every escape in one folder that every worktree finds, and each file describes its bug, so add-reviewer needs no git host. The migration writes one file per old line (its link as `source`, the body "Migrated; see source.") and keeps the old file. To migrate into a folder other than the default, set it up first ("Setting up escapes").
2. **On yes:** `bash <this skill's base directory>/../add-reviewer/escape-migrate.sh <repo-root>`. A second run adds nothing.
3. **The steps it prints:** removing the old file, setting the `escapes` folder, and removing `REVIEW_ROUTING_ESCAPES` from the `env` block of `.claude/settings*.json`. Run each only after the user agrees, then record the escape again. On no: record nothing, and say that recording waits for the migration.

## Recording by hand

Only when `escape-add.sh` cannot run or fails for a reason other than its own answer: bash or the script is missing ("command not found", "No such file or directory"), or it exits with a code other than 0, 2, 3 or 6. Exit 2 is a wrong argument: correct it and run the script again. Exit 3 and 6: follow "What the script answers" above. Do these steps exactly, then tell the user that the script failed (quote its error) and that you wrote the file by hand.

1. **The folder.** The main worktree is the first `worktree` line of `git worktree list --porcelain`. The `escapes` setting comes from `REVIEW_ROUTING_ESCAPES`, else the last `escapes=` line of `<main worktree>/.claude/mash-workbench/settings.local`, else of `settings` there. `off`: record nothing and stop. A relative value is from the main worktree. A value from `settings` (the committed file) that names a folder outside the main worktree is not a choice the user made: do not use it, and ask the user. Not set: if `docs/mash/review-escapes.md` or `docs/review-escapes.md` exists there, or the value names a file, follow "Migrating an old ledger"; else ask as in "Setting up escapes".
2. **Check the folder.** Never inside a linked worktree, the git directory, `/tmp` or `$TMPDIR`, and never through a symbolic link (`.claude/mash-workbench`, the folder itself, or its `README.md`). Outside the main worktree, a `README.md` there must name this repository on its `repo:` line.
3. **Check the fields.** The area is a directory inside the repository (never a file, never `.`, never absolute, no `..`, no whitespace): drop a leading `./`, a trailing `/`, and turn `//` into `/`. The class and the slug are lowercase letters and digits in words joined by `-`; the slug has at most 60 characters. If a field fails, ask the user for a correct value.
4. **Normalise the source link**, as the last paragraph of "Recording escapes" says. Anything that is not an http(s) link, `owner/repo#N` or `#N`: ask for a link, or record without one.
5. **Duplicates.** If a `.md` file in the folder (not in `processed/`) has this `area:` and the line `source: <link>`, write nothing and say "already recorded". A GitHub `/pull/N` and `/issues/N` with no fragment are the same link.
6. **New folder.** Create it with a `README.md` holding these lines, where `repo:` is the origin remote as `host/owner/repo`, lowercased (with no origin, `local/<main worktree folder name>`):

   ```text
   # Review escapes
   repo: github.com/acme/shop

   One file per bug that a review passed. The add-reviewer skill reads them through escapes-report.sh.
   ```

7. **Write the file** `<folder>/<YYYY-MM-DD>-<slug>.md`, dated today in UTC (`date -u +%F`); if the name exists, in the folder or in `processed/`, add `-2`, `-3` and so on before `.md`. Leave out the `source:` line when there is no link. One empty line separates the frontmatter from the body. Example:

   ```text
   ---
   date: 2026-11-21
   area: src/billing
   class: wrong-result
   source: https://github.com/acme/shop/pull/12#discussion_r222
   ---

   When the order has a discount, the total includes tax. The total must not include tax. Tax is a separate line.
   ```

8. **Threshold.** Count the files with this area (files with the same `source` once). At the threshold (default 3, or the `escapes.threshold` setting), unless `declined.<area>=<date>:<count>` is set and the count is below `<count>` + 2, tell the user: "<area>: N escapes -> add a reviewer for <area> (add-reviewer skill)".

## Common mistakes

| Mistake                                                                    | Instead                                                          |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Picking reviewers from the file names you remember                         | Run `route`; docs, scripts and `.claude/` may have reviewers too |
| Reading a non-zero exit as "no reviewers needed"                           | Fix the range or config and run it again                         |
| Skipping `review-routing:change-reviewer` because "it's a small change"    | Every agent the script prints is dispatched                      |
| Letting reviewers run the suite and linters                                | Run them once; pass the results in each prompt                   |
| Dispatching reviewers while a test, linter or formatter is red             | Fix the deterministic failures first                             |
| Running a check command `find-checks.sh` listed without asking             | It lists candidates; the user confirms                           |
| A clean verdict reported with no checks having run                         | Say **Unchecked** in the summary                                 |
| A reviewer flags formatting, style or a convention and the fix stops there | Automate it (test, lint rule, formatter, hook)                   |
| Re-reviewing the whole change after a small fix                            | Send the fix's diff to the reviewers Fix rounds step 3 names     |
| Starting a fix-round reviewer without a model                              | Use the model SKILL.md step 1 (`route <range> --models`) gave it |
| Fixing an old bug a reviewer spotted inside this change                    | List it as Pre-existing; one concern per change                  |
| Counting a reviewer that crashed or gave no verdict as safe                | Dispatch it again                                                |
| Calling the branch ready while a reviewer said `NOT SAFE`                  | Every last verdict must be `SAFE TO LAND`                        |
| Committing escape files on the fix branch                                  | The user commits them from the main worktree                     |
