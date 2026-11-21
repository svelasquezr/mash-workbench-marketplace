# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

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
