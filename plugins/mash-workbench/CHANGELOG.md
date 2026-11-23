# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

## 0.3.0 - 2026-11-22

The tooling backlog now uses the same settings and the same path checks as review-routing's escapes, and security bugs are corrected; `docs/decisions/0006-scripts-trust-no-input.md` in the marketplace repository has the details.

**The interface of `backlog-add.sh` changed.** `--create` and `--file <path>` are gone: the place of the backlog is the `backlog` setting, which you choose once (`mash-settings.sh set <repo-root> backlog <path, or off> --team` or `--local`). A session that uses an old option gets exit code 2 and the new form. `MASH_WORKBENCH_BACKLOG` in your environment still works and still wins. A backlog that exists at `docs/mash/tooling-backlog.md` or `docs/tooling-backlog.md` keeps working; the skill asks once whether to keep it there or move it.

**The backlog is read from the main worktree.** A session in a linked worktree used to write `docs/mash/tooling-backlog.md` in that worktree. It now writes the main worktree's file, as every other worktree does. The new line waits there as an uncommitted change.

Fixed:

- When a project folder contained `datetime.py` or `re.py`, `backlog-stale.sh` ran it: the script gave its Python program to the interpreter with the current folder on the module path. `backlog-stale.sh` is now plain bash, and `scripts/python.sh` starts Python isolated (`-I -B`).
- When a repository contained a symbolic link at `docs/mash/tooling-backlog.md`, at `docs/tooling-backlog.md` or at a folder on that path, `backlog-add.sh` appended its line to the file that the link named, for example a shell startup file. The script now stops with exit code 6.
- When `MASH_WORKBENCH_BACKLOG` or `--file` named a path, `backlog-add.sh` wrote there with no check. The path now gets the checks of the escapes folder: no linked worktree, no temporary folder, no git directory, no file that a different repository owns. The committed settings file cannot select a file outside the repository. A committed `settings.local` (also behind a `.claude` link or in a submodule) is read as a committed file. A committed folder shaped like a git directory no longer makes git run a committed program or count a committed `settings.local` as yours: `mash-settings.sh` starts git only in a repository that a real `.git` entry names, and a `settings.local` counts as yours only with the exclude line that `set --local` writes (see the `review-routing` 0.6.0 entry).
- When the committed settings file named a different file of the repository (for example `backlog=.env`), `backlog-add.sh` put a `repo:` line and its entry into that file. The script now writes only to a new file, an empty `.md` file, or a file whose first line is `# Tooling backlog`; for each other file, and for a file it cannot read, it stops with exit code 6.
- With the allow rule, a session could make `backlog-add.sh` write into any other repository on the machine by naming it as `<repo-root>`. A line now goes only to the repository of the current folder (outside git: a folder that holds the current folder, when the current folder is outside git too).
- `backlog-stale.sh` and the near-duplicate note of `backlog-add.sh` printed backlog entries with their control characters; they now remove them. `backlog-add.sh` refuses a `<repo-root>` whose name holds a control character, a tab or a line feed (exit 6), and `mash-settings.sh` refuses such a repository path. On Windows (Git Bash), `permission-rules.sh` offers no allow rule, because the checks are not tested there.

Changed scripts:

- `skills/scout/backlog-add.sh`: no `--create` and no `--file`; exit 3 prints the `mash-settings.sh set` commands; a new file starts with a title and a `repo:` line, and an old file with a title gets the `repo:` line on the next write; exit 6 for a refused path; it says on stderr when an old backlog has no setting yet; it runs `plugin-current.sh` first.
- `skills/scout/backlog-path.sh`: reads the `backlog` setting through `mash-settings.sh path` from the main worktree; exit 5 and 6 are new.
- `skills/scout/backlog-stale.sh`: plain bash, no Python; the same output.
- New `skills/scout/permission-rules.sh` (the same file as in review-routing): prints the one allow rule to offer, `Bash(bash <installed path>/skills/scout/backlog-add.sh *)`, and the old rules to remove first.
- `scripts/python.sh`, `scripts/mash-settings.sh` and the new `scripts/plugin-current.sh` are the same files as in review-routing 0.6.0; its CHANGELOG entry describes them.

Other:

- The README has a new section, "Audit this plugin": what each script reads and writes, who can choose the backlog file, the permission prompt, the optional allow rule and its limits, and a prompt you can give your own agent. A second new section, "Pin a version", says how to stay on one commit of the marketplace.
- `scout` has a `reference.md`: "Setting up the backlog", "Old backlog file" and "What the script answers". `forge` no longer says that stale entries need Python.

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
