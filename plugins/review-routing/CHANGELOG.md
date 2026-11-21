# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

## 0.5.1 - 2026-11-21

Security fix. When you had added the allow rules that "Setting up escapes" offered in 0.4.0 to 0.5.0, Claude Code ran each command that started with `bash` and contained the script name, with no prompt. Examples are `bash -c '<a command>' /review-routing/add-reviewer/escape-add.sh` and `bash <a different script> /x/review-routing/add-reviewer/escape-add.sh`. The cause is that `*` in a rule matches all text, spaces included, and the rules had a wildcard before the script path. Only the plugin's own scripts must run with no prompt.

**Remove the old rules now.** Open `.claude/settings.local.json` in the main worktree of each repository where you accepted the offer (and any other settings file you copied them to), and delete these lines from `permissions.allow`:

```text
Bash(bash */review-routing/*add-reviewer/escape-add.sh*)
Bash(bash */review-routing/*add-reviewer/escape-migrate.sh*)
Bash(bash */review-routing/*review-changes/review-log.sh*)
Bash(bash */review-routing/*scripts/mash-settings.sh*)
```

Delete also any other rule for these scripts that has a `*` before the script path. Then, if you want sessions with no user to keep recording without a prompt, run step 3 of "Setting up escapes" (in the `review-changes` `reference.md`) again: it offers the new rules and names the old ones it finds.

Changed scripts:

- New `skills/review-changes/permission-rules.sh <repo-root>`: prints the allow rules to offer, and the old rules to remove. Each rule is `Bash(bash <script path> *)` with the exact path of the installed plugin and one wildcard, at the end; there is one rule for each spelling of the path that a skill writes, and only for `escape-add.sh` and `review-log.sh`. It reads the `Bash(...)` strings of `.claude/settings.local.json` in the main worktree (and in the current linked worktree), and prints `present:`, `add:` and `remove:` lines; a `remove:` rule is a `Bash(bash ...)` rule that is not a current rule and names one of the plugin's scripts under a `review-routing` folder or after a wildcard. It does not tell the `allow`, `deny` and `ask` lists apart. It writes nothing and makes no network call. It exits 6 and prints no rule when the plugin folder, or a symbolic link on the path to it, is inside a worktree of the repository (a session that edits files there could change the scripts), or when the plugin path holds a character a rule cannot spell safely.

Other:

- "Setting up escapes" step 3 runs that script and no longer shows a fixed list of rules. `escape-migrate.sh` and `mash-settings.sh` get no rule any more: they run only after you answered a question, so you are there to approve them.
- The rules name the plugin's version folder, so they stop matching after each plugin update, on purpose: a new version's scripts run with no prompt only after you allowed them again. Run step 3 again after an update.
- "Recording escapes" says what a session with no user does when Claude Code refuses the command: it tries no other spelling and no wrapper, and puts the escapes in its final report for a session with a user to record.
- Added `docs/decisions/0005-exact-path-allow-rules.md`, with the Claude Code test results; decision 7 of 0004 points to it.
- New test `tests/test_permission_rules.sh`.

## 0.5.0 - 2026-11-21

New skill `record-escape`: when you process review comments, paste one, or correct code that a review passed, it records the bug as an escape file, but only when a review passed the code and the problem is a behavior bug. To know whether a review passed the code, `review-changes` now keeps a log of the ranges it reviewed. The log stays on your machine and is never committed.

Changed scripts:

- New `skills/review-changes/review-log.sh`: `add <repo-root> <base> <head>` appends a line to `reviews.log` in the main worktree's `.claude/mash-workbench/` folder (and lists that file in the repository's `info/exclude`). The line holds the base and head commits and the patch-ids of the range and of each commit. `reviewed <repo-root> <commit>` exits 0 when a logged range holds the commit, or when the commit's diff equals the range's diff (a squash merge) or one commit's diff (a rebase merge or cherry-pick). That still works after the branch is deleted and `git gc` removes its commits. It exits 1 when the log has no answer. It never writes anywhere else and makes no network call.
- `skills/add-reviewer/escape-add.sh`: when the same source is already recorded in another area, the escape is still recorded, and the script now prints "also recorded in <area>: <file>" after the "recorded" line (after the summary line for `--batch`).
- `review-log.sh` makes every diff with `git diff-tree` (plumbing, from the main worktree), so `diff.submodule`, `diff.ignoreSubmodules` and `diff.relative` do not change an id either, and the id of a one-commit range is that commit's id. It uses fixed options (no color, no external diff, no text conversion, no rename detection, `a/` and `b/` prefixes, `--binary`), so the patch-ids do not change with the user's `color.ui`, `diff.external`, `diff.noprefix` or `diff.renames`. `add` refuses a base that is not an ancestor of the head, and a range with no changes (exit 2), and exits 6 without logging when a patch-id cannot be computed. `reviewed` computes the commit's own patch-id once. Its header states the limits: a squash merge with conflict fixes does not match, and a change that differs only in whitespace has the same patch-id.
- `review-log.sh add` checks that the record is one line of exactly five fields before it appends (exit 6, nothing written, otherwise). A per-commit patch-id that fails is skipped, so it never writes a second line. The header names one more limit: a `.gitattributes` change on the reviewed branch that changes whether a file counts as binary makes a later squash merge miss, and the skill then asks the user.
- `skills/add-reviewer/escapes-path.sh`: only a comment change. The header now says that the refusal of the repository root (exit 6) applies inside a git repository only.

Other:

- `review-changes` step 5: when every last verdict is `SAFE TO LAND`, it logs the range with `review-log.sh add`, and adds a summary line, with the question about a specialist reviewer, for each area at or over the escape threshold that is not declined. It also says "N escape files wait uncommitted in <folder>" when committed escapes wait. The details are in the new "Review log and escape lines" section of its `reference.md`.
- The "Setting up escapes" section of the `review-changes` `reference.md` says what to do when `mash-settings.sh set` exits 1 (the settings lock is held): run it again; if it persists, check that no other session writes, then remove the lock folder the message names. The offered allow rules now include `review-log.sh`.
- Fixed in the `review-changes` `reference.md` ("Recording escapes" and the new section): the count of "escape files wait uncommitted" now uses `git status --porcelain --untracked-files=all` on the escapes folder and leaves out `README.md`. Before, a new folder was counted as one entry, and `README.md` counted as a file.
- The plugin description now names `record-escape`.
- An escape's body is one paragraph on one line (sentences separated by spaces): `escape-template.md`, the "Recording escapes" and "Recording by hand" text and the `record-escape` skill say so.
- New test `tests/test_skill_script_paths.sh`: every script path in a `SKILL.md` or `reference.md` names a file that exists.

## 0.4.1 - 2026-11-21

Fixed: when the `escapes` setting was empty (for example `escapes=` in a settings file), the escapes folder became the repository root. Escape files and a `README.md` were then written into the root, and the report counted every `.md` file there. An empty setting now counts as not set, so a repository with no setting, or with an old ledger, behaves as before. A setting that names the repository root is refused. A setting of only spaces or tabs also counts as not set; before, it made a folder named " " in the repository root.

Changed scripts:

- `scripts/mash-settings.sh`: `get` treats an empty or whitespace-only value as not set (exit 3, or the next source answers; a later empty line for a key hides an earlier value in the same file). `set` refuses such a value with exit 2 and points at `unset`. `check-escapes-path` refuses the repository root itself with exit 6.
- `skills/add-reviewer/escapes-path.sh`: exits 6 with "the escapes folder must not be the repository root" when the setting resolves to the main worktree.

## 0.4.0 - 2026-11-21

Escapes are now one file per bug, in one folder that every worktree finds. Nothing new is recorded into an old one-line ledger: migrate it first.

Changed scripts:

- `skills/add-reviewer/escape-add.sh` (rewritten): records one escape as `<escapes folder>/<date>-<slug>.md`, with `date`, `area`, `class` and an optional `source` in its frontmatter and the bug's description as its body (`--body-file`). The escapes folder comes from the `escapes` setting; with none chosen it exits 3 and prints the `mash-settings.sh set` commands to choose it. It checks the folder with `mash-settings.sh check-escapes-path` (exit 6 when refused), writes a `README.md` with the owning repository's `repo:` line on the first record, and skips an escape whose area and source the folder already holds (a GitHub `/pull/N` and `/issues/N` with no fragment count as one source). A file name that `processed/` already holds is not used again. A setting that names a missing `.md` file is refused, not created as a folder. `--batch <file>` records several (all checked first, nothing written when one is wrong), and `--list <area>` prints an area's escapes, newest first. GitHub pull request links now stay `/pull/N`, and a review comment keeps its `#discussion_r<id>` fragment (`#r<id>` becomes that), as do `#issuecomment-<id>` and `#pullrequestreview-<id>` on a pull request, so two comments on one pull request are two escapes. A pull request's `/changes` page is the pull request, like `/files`. Paths in the commands it prints are quoted. With an old ledger file in use it exits 3 and writes nothing. `--create` and `--file` are gone. It now refuses a repository root that is not a git repository; an escapes folder outside the repository is still allowed.
- `skills/add-reviewer/escapes-report.sh`: counts the escape files per area (not `README.md`, not `processed/`). The threshold is now 3 by default, set with the `escapes.threshold` setting; `--threshold N` still wins. It notes when more than half of an area's escapes come from one pull request, and a `declined.<area>` setting hides the "add a reviewer" suffix until the area has two more escapes. An old ledger file is still counted, with "old ledger format: run escape-migrate.sh" on stderr.
- New `skills/add-reviewer/escape-migrate.sh`: turns each line of an old ledger (`docs/mash/review-escapes.md`, `docs/review-escapes.md`, or a file the `escapes` setting names) into an escape file with the line's link as `source`. One link in two areas stays two escapes, as the old report counted it. An entry that fails the checks is named by its old file and line, and nothing is written. It never deletes the old file or changes a setting; it prints those commands, with quoted paths.
- `scripts/mash-settings.sh`: new `unset <dir> <key> --local|--team` removes a key's lines under the same lock as `set`; the `add-reviewer` reference uses it to clear `declined.<area>` after a reviewer lands.
- New `skills/add-reviewer/escape-fields.awk`: reads the frontmatter of escape files for `escape-add.sh` and `escapes-report.sh`.
- `skills/add-reviewer/escapes-path.sh`: the old-ledger message is now "old ledger format in use: <path>; run escape-migrate.sh", and it warns whenever an old ledger file exists next to an escapes folder setting.

Other:

- New `skills/add-reviewer/escape-template.md`, an example escape file.
- The `review-changes` reference has new "Setting up escapes" (including the offer to add allow rules for the recording scripts to `<main worktree>/.claude/settings.local.json`) and "Migrating an old ledger" sections, and "Recording escapes" and "Recording by hand" describe the file format. The `add-reviewer` reference has a new "Escape evidence" section: a subagent drafts the checklist from the area's escape files, which move to `processed/` once the reviewer lands.
- The `add-reviewer` description and the README say "the escape threshold (default 3)" instead of "twice".

## 0.3.4 - 2026-11-21

Changed scripts:

- New `scripts/mash-settings.sh`: finds the main worktree from any worktree, reads and writes the settings files in `<main worktree>/.claude/mash-workbench/` (`settings` for the team, `settings.local` for you, added to the repository's `info/exclude`), checks a proposed escapes folder, and prints the repository key. Nothing calls it to write yet.
- `skills/add-reviewer/escape-add.sh`: a relative `--create` or `--file` path is now from the main worktree, so a ledger started from a linked worktree is found again. `escapes=off` in the settings files now stops `--create` and `--file` too, not only the environment variable.
- `skills/add-reviewer/escapes-path.sh`: reads the `escapes` setting through `mash-settings.sh` (environment variable `REVIEW_ROUTING_ESCAPES`, then `settings.local`, then `settings`), and resolves a relative path and the old `docs/mash/review-escapes.md` and `docs/review-escapes.md` from the main worktree, not from the current worktree. A linked worktree now finds the same ledger as the main one. It prints "old ledger file in use: <path>" on stderr when it falls back to an old file. Outside a git repository it still uses the given folder and reads only `REVIEW_ROUTING_ESCAPES`, as before. It exits 5 in a bare repository when no absolute path is set.

Other:

- Added `docs/decisions/0004-escape-storage-and-settings.md`.
- The README and the `review-changes` reference say that a relative ledger path is from the main worktree, and that you commit a new entry there, not on the fix branch.

## 0.3.3 - 2026-11-21

Changed scripts:

- Removed the hook `hooks/haiku-reviewer-guard.py` and its `Agent|Task` entry in `hooks/hooks.json`. The plugin no longer blocks an Agent call that starts a reviewer on Haiku.
- `hooks/reviewer-guard.py`: no change in behavior (only its docstring changed).

Other:

- The router never prints Haiku, and `review-changes` tells the session to use the models it prints. Nothing checks a direct dispatch or a fix-round dispatch any more.
- The README, the `inspect` skill and the `add-reviewer` reference now say that the router, not a hook, keeps Haiku out.
- Added this changelog.
