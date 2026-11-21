# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

## 0.2.5 - 2026-11-21

Fixed: an empty setting, such as `escapes=`, was read as a real value. For the escapes setting this made review-routing write files into the repository root.

Changed scripts:

- `scripts/mash-settings.sh` (the same file as in review-routing): `get` treats an empty or whitespace-only value as not set (exit 3, or the next source answers; a later empty line for a key hides an earlier value in the same file). `set` refuses such a value with exit 2 and points at `unset`. `check-escapes-path` refuses the repository root itself with exit 6.

## 0.2.4 - 2026-11-21

Changed scripts:

- `scripts/mash-settings.sh`: new `unset <dir> <key> --local|--team` removes a key's lines under the same lock as `set` (the same file as in review-routing). Nothing in this plugin calls it yet.

Other:

- `forge` and the README describe review-routing's new escape files (`.claude/mash-workbench/escapes/` by default) and the escape threshold (default 3) instead of the old ledger file and "two or more".

## 0.2.3 - 2026-11-21

Changed scripts:

- New `scripts/mash-settings.sh`, the same file as in review-routing: finds the main worktree from any worktree, reads and writes the settings files in `<main worktree>/.claude/mash-workbench/`, and checks a proposed folder. Nothing in this plugin calls it yet; the backlog moves to it in a later version.

Other:

- None.

## 0.2.2 - 2026-11-21

Changed scripts:

- None.

Other:

- Added this changelog. No other change in this plugin.
