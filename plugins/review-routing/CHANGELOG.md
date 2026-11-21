# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

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
