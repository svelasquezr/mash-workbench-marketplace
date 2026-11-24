# migrate reference

## Inventory

From mash-workbench 0.x. Read everything in the main worktree, and also the current linked worktree's own `.claude/settings.local.json`:

- `.claude/mash-workbench/settings` (committed) and `.claude/mash-workbench/settings.local` (yours): the last `backlog=` line of each. `settings.local` wins. A value is a path relative to the repository top, an absolute path, or `off`. Other keys (`escapes`, `escapes.threshold`, `declined.*`) belong to the review plugin: leave them, and say that `/mash-review:migrate` handles them.
- the line `.claude/mash-workbench/settings.local` in `.git/info/exclude` (`git rev-parse --git-common-dir` names the folder);
- `.claude/mash-workbench/.settings.lock` and `.settings.<number>.tmp` files: leftovers of an interrupted write;
- `docs/mash/tooling-backlog.md` and `docs/tooling-backlog.md` (the 0.x defaults), and `.mash-workbench/tooling-backlog.md` (the 1.0 default);
- allow rules in `.claude/settings.local.json` and `.claude/settings.json` (main worktree, and the current linked worktree's `.claude/settings.local.json`) that name `backlog-add.sh`, `backlog-path.sh`, `backlog-stale.sh`, `permission-rules.sh`, `past-friction.py`, `python.sh`, `mash-settings.sh` or `plugin-current.sh` in a `mash-workbench` folder;
- `MASH_WORKBENCH_BACKLOG` and `MASH_PYTHON` in the `env` blocks of `.claude/settings*.json`. A `MASH_WORKBENCH_BACKLOG` value ranks above the `backlog=` lines, as in 0.x;
- a location line `Tooling backlog: …` in `CLAUDE.md`, `AGENTS.md` or `.github/copilot-instructions.md`;
- a `<backlog file>.<number>.tmp` file next to the backlog (an interrupted write), and a `.gitignore` line for the backlog file (0.2.x offered one): with a committed backlog, propose to remove that line.

## Proposal

One item each:

- **Allow rules and `env` entries to remove, first.** The rules still approve the old scripts that Claude Code keeps in its plugin cache after an update. `MASH_WORKBENCH_BACKLOG` no longer has an effect; its value goes into the location item below. Tell the user to check other settings files they copied rules to (`~/.claude/settings.json`, other worktrees), and their shell profile for the two variables.
- **The 0.x choice (`MASH_WORKBENCH_BACKLOG`, else the `backlog` setting) → a location line.** The line goes to `CLAUDE.md` when it exists; else to `AGENTS.md` when it exists (Claude Code reads `AGENTS.md` only where there is no `CLAUDE.md`, and a new `CLAUDE.md` would hide it); else to a new `CLAUDE.md`. A path inside the repository: `Tooling backlog: <path>`. `off`: `Tooling backlog: off`. A 0.x default path (`docs/mash/tooling-backlog.md`, `docs/tooling-backlog.md`): no line; the next item moves the file. A path outside the repository: 1.0 keeps the backlog inside the repository, so propose to move the file into it (to `.mash-workbench/tooling-backlog.md`) and name the old file in the report; never write a location line with an outside path. A location line already there wins: propose only to delete the setting.
- **Old backlog files** (`docs/mash/tooling-backlog.md`, `docs/tooling-backlog.md`). Pick the first case that fits:
  - A location line, or a 0.x path inside the repository that is not an old default, names the active backlog: never move or delete the file it names. (A 0.x path outside the repository moves to `.mash-workbench/tooling-backlog.md`, as the item above says; that file is then the active backlog.) Name each other old default file in the proposal, with the choice to append its entries to the active backlog (then delete it) or to leave it.
  - Exactly one old default file and no `.mash-workbench/tooling-backlog.md`: create `.mash-workbench/` and `git mv` the file to `.mash-workbench/tooling-backlog.md` (a plain `mv` when git does not track it; then propose to remove its `.gitignore` line), or keep it with the line `Tooling backlog: <its path>`; recommend the move. The moved file keeps its title and its `repo:` line.
  - Two or more of these three files exist (the two old defaults and `.mash-workbench/tooling-backlog.md`): propose to append every entry of the old files, open and closed (`- [x]` lines keep the history), without their title and `repo:` lines, to `.mash-workbench/tooling-backlog.md`, then delete them. A new target file first gets `# Tooling backlog` and a blank line.
- **Old entries to delete:** the `backlog` lines; then each settings file with no key left; the exclude line, when `settings.local` is deleted; the lock folder and the `.tmp` files (also the one next to the backlog); `.claude/mash-workbench/` when it is empty. A settings file that still holds review keys stays.
- **Text to rewrite:** project text that names `/forge` steps with scripts (`backlog-add.sh`, `past-friction.py`), or the `backlog` setting: point it to the location line.

A file whose first line is not `# Tooling backlog` is not a backlog: report it, and do not move it or name it in a location line.
