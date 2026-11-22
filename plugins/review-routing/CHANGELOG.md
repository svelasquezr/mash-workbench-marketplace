# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

## 0.6.0 - 2026-11-22

Security hardening, and the audit documentation. Seven security bugs are corrected; `docs/decisions/0006-scripts-trust-no-input.md` in the marketplace repository has the conditions, the incorrect result and the expected result of each one.

**Do this after you update.** If you accepted allow rules from an earlier version, run step 3 of "Setting up escapes" (in the `review-changes` `reference.md`) again. Claude Code keeps the folder of the old version in its plugin cache, and your old rules continue to approve the old scripts, with their bugs, with no prompt. `permission-rules.sh` now lists those rules as `remove:` lines and offers no new rule until they are gone.

**The interface of `escape-add.sh` changed.** `--body-file <file>` is gone: pass the text with `--body "<text>"`. One record reads no file and no standard input. `--batch` reads standard input only (`--batch - <repo-root>`). A session that uses the old form gets exit code 2 and the new form.

Fixed:

- When you had an allow rule for `escape-add.sh`, a session ran `escape-add.sh ... --body-file <file>` with no prompt, and the script copied that file, for example a private key, into the escapes folder. The script must not open a file that an argument names. It now takes the body as text.
- When the committed file `.claude/mash-workbench/settings` named an escapes folder outside the repository (for example `escapes=../victim/.claude/rules`), `escape-add.sh` wrote there with no question. Only your own `settings.local` or the environment variable can select a place outside the repository. The scripts now stop with exit code 6, and the session asks you. A `settings.local` is your own file only when git answers that the main repository's index does not track it: a repository can commit one, directly, behind a committed `.claude` link, or in a submodule at `.claude/mash-workbench`. The scripts then read it as a committed file, or stop.
- When a repository committed a folder shaped like a git directory (`HEAD`, `objects/`, `refs/` and a `config`), at `.claude/mash-workbench` or at a folder that a `<repo-root>` argument named, git took it as a repository: it ran the program that the committed config named in `core.fsmonitor`, and a committed `settings.local` counted as yours. The scripts now start git only in a repository that a real `.git` entry names, and stop with exit code 6 otherwise. A bare repository's own folder now gets exit code 6, not 5.
- When a patch applied with `git apply` created `.claude/mash-workbench/settings.local`, the file counted as yours. A `settings.local` now counts as yours only when the exclude line that `mash-settings.sh set --local` writes is in the repository's `info/exclude`. A file you wrote by hand counts after one `set --local`. The line stays when the file is deleted, so a file that a patch creates after that still counts as yours (an accepted limit).
- When `.claude/agents` was a committed symbolic link to a folder outside the repository, the router read agent files there and printed their `model:` value. It now reads no agent file outside the repository.
- In a partial clone, `review-log.sh` could download missing objects (a network call). It no longer does: git 2.44 and later get `GIT_NO_LAZY_FETCH`, and with an older git it stops (exit code 6).
- With an allow rule, a session could make `escape-add.sh` or `review-log.sh add` write into any other repository on the machine by naming it as `<repo-root>`. A write now goes only to the repository of the current folder (exit code 6 otherwise).
- A committed `reviews.log` answered `reviewed` for code that no review passed, and `add` appended to it. A tracked log is now refused by `add` and not read by `reviewed`.
- Text that a committed escape file holds reached the terminal with its control characters (an escape sequence can hide or rewrite text). The scripts now remove them from what they print, and refuse a settings path with one.
- On Windows (Git Bash), where the checks are not tested, `permission-rules.sh` offers no allow rules; each run asks you. CI now also runs the tests on macOS.
- When a repository contained a symbolic link at `.claude/mash-workbench`, at the escapes folder, at its `README.md` or at `reviews.log`, the scripts wrote to the place that the link named. They now stop with exit code 6. The reports do not read an escape file that is a symbolic link. When `settings` or `settings.local` was a symbolic link to a private file, `mash-settings.sh set` copied the lines of that file into the settings file. A settings file that is a symbolic link is now refused. An old ledger file that is a symbolic link, or that is behind a linked `docs` folder, is refused by `escapes-path.sh`, `escapes-report.sh` and `escape-migrate.sh`.
- When a project folder contained `datetime.py`, `re.py` or a different module name of the standard library, plugin Python could import and run it. `scripts/python.sh` now starts Python, and its version probe, isolated (`-I`).
- When you updated the plugin and kept the old allow rules, the scripts of the old version in the plugin cache continued to run with no prompt. From this version on, `escape-add.sh` and `review-log.sh` stop with exit code 6 when their copy is not an installed version.
- When the range given to the router started with `-` (for example `--output=<file>`), git read it as an option and wrote the file. The router now refuses such a range.
- When `.claude/reviewers.toml` named a reviewer with `/` or `..` in the name, the router read an agent file outside the agents folders. It now reads no file for such a name.

Changed scripts:

- `scripts/python.sh` (the same file in both plugins): only `MASH_PYTHON` can be a file name with spaces, and only when it holds `/` or `\`; a project file named `py -3` no longer changes how any candidate is read. It runs the interpreter with `-I -B`, and sets `PYTHONSAFEPATH=1` and `PYTHONDONTWRITEBYTECODE=1`. Python does not import from the current folder or from `PYTHONPATH`, and writes no `__pycache__`.
- `scripts/mash-settings.sh` (the same file in both plugins): new `toplevel <dir>`; exit 6 from every command in a folder shaped like a git directory, and for a submodule or a nested repository at the home folder; new `source <dir> <key>` (prints `env`, `local` or `team`), `path <dir> escapes|backlog` (the place a key names, with `.` and `..` removed as text before the checks, and with the refusals above) and `check-backlog-path <dir> <path>`. `home`, `get`, `source`, `path`, `set` and `unset` exit 6 when `.claude/mash-workbench` is a symbolic link or `.claude` leads outside the main worktree. `check-escapes-path` also refuses a symbolic link that leads from inside the repository to outside, a link as the folder, a path with a backslash, and `/var/tmp`. `get`, `source`, `path`, `set` and `unset` exit 6 when a settings file is a symbolic link; a `settings.local` that git tracks, that is in a submodule or a nested repository, or about which git gives no answer, is read as a committed file (`source` prints `team`), and `set --local` refuses to write it. A symbolic link at `.claude` is refused also when it stays inside the repository. `path` keeps a drive letter as written (`C:/Users/me/escapes`, not `/C:/...`) and refuses a setting that names a link to a file.
- New `scripts/plugin-current.sh` (the same file in both plugins): exit 6 when the copy it is in is in Claude Code's plugin cache and `installed_plugins.json` does not list it for you or for the project of the current folder (an entry of another project does not count). It reads only that file, and asks `mash-settings.sh` for the top folder and the main worktree of the current folder (no git starts in a folder shaped like a git directory).
- `skills/add-reviewer/escape-add.sh`: `--body <text>` replaces `--body-file` (no file and no standard input is read for one record); `--batch -` reads standard input only; it refuses a `README.md` that is a symbolic link; it runs `plugin-current.sh` first; `--list` and the duplicate check skip symbolic links.
- `skills/add-reviewer/escapes-path.sh`: uses `mash-settings.sh path`, so exit 6 now also covers a place outside the repository that the committed settings file names, a symbolic link, and an old ledger file that is a symbolic link.
- `skills/add-reviewer/escapes-report.sh`: skips escape files that are symbolic links.
- `skills/add-reviewer/escape-migrate.sh`: gives its entries to `escape-add.sh` on standard input; exit 6 when an old ledger file, or a folder on its path, is a symbolic link.
- `skills/review-changes/review-log.sh`: runs `plugin-current.sh` first; runs git only in the main worktree or the top folder that `mash-settings.sh toplevel` prints, without the git variables that choose another repository or config, and with no fsmonitor program (the same in `escape-add.sh`, `escape-migrate.sh` and `permission-rules.sh`); exits 6 when the home folder or `reviews.log` is a symbolic link; refuses a revision that starts with `-`; gives only full commit ids from the log to git.
- `skills/review-changes/permission-rules.sh` (now the same file as `skills/scout/permission-rules.sh` in mash-workbench): reads which list each rule is in, so `present:` and `remove:` are about `allow` lists only, and a note names a current rule that a `deny` or `ask` list also holds; prints no `add:` line while a `remove:` line is there; says which other settings files to clean by hand.
- `skills/review-changes/reviewers-for-change.py`: refuses a range that starts with `-` or holds whitespace (exit 2). `route_models.py`: a reviewer name with `/`, `\` or a leading `.` names no agent file, and an agent file that is a symbolic link is not read.
- `scripts/mash-settings.sh repo-key`: an origin that is a path on your machine gives `local/<folder name>`, not the path.
- `skills/review-changes/find-checks.sh`: drops control characters from the command lines it prints.
- `hooks/reviewer-guard.py`: only its docstring changed (two more known gaps are listed).

Other:

- The README has a new section, "Audit this plugin": what each script reads and writes, who can choose the escapes folder, what the hook refuses, the permission prompt and its exceptions, the allow rules and their limits, the Python 3.11 note, the sandbox settings, and a prompt you can give your own agent. A second new section, "Pin a version", says how to stay on one commit of the marketplace.
- The marketplace repository has two new tripwire tests, `tests/test_no_network.sh` (no plugin file holds a network word outside a list of accepted lines) and `tests/test_write_scope.sh` (each script changes only the places the README lists, in the four folders the test watches). Neither is proof; the README says what they do not see.
- `record-escape` and the `review-changes` reference use `--body`, say what each exit 6 message means, and make removing old allow rules the first part of setup step 3.

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
