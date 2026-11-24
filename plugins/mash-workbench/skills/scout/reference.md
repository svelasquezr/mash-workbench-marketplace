# scout reference

The design, with diagrams, is `docs/specs/mash-workbench.md` in the marketplace repository.

## Main worktree

The first `worktree` line of `git worktree list --porcelain`. When the line after it is `bare`, that entry is the git directory of a bare repository: use the top of the current worktree (`git rev-parse --show-toplevel`) instead. Outside git: the project folder. The location line, the backlog and the 0.x files are read and written there only, so every worktree finds the same ones. In a bare repository each worktree keeps its own backlog: say that its new lines must be committed before the worktree is removed.

## First time

There is no location line and no `.mash-workbench/tooling-backlog.md`. Ask the user once, in one question, with a recommendation:

- `.mash-workbench/tooling-backlog.md`, committed (recommended: the plugin's own folder, like `.mash-review/` of the mash-review plugin; the whole team's candidates add up, and the reasons are reviewable). It needs no line: go on with "The file".
- Another file in the repository. Propose the line `Tooling backlog: <path>` ("Where the line goes" below, in the main worktree), and write it only on a yes.
- None. Propose the line `Tooling backlog: off`, and write it only on a yes. Then write nothing.

A no to the line: use the answer for this session only; a later session asks again.

## Where the line goes

The line goes to `CLAUDE.md` when it exists; else to `AGENTS.md` when it exists (Claude Code reads `AGENTS.md` only where there is no `CLAUDE.md`, and a new `CLAUDE.md` would hide it); else to a new `CLAUDE.md`. Copilot CLI reads `.github/copilot-instructions.md` and `AGENTS.md`; when the project uses Copilot CLI, offer the same line there too.

## The file

Write to the backlog only when every answer is yes:

- The path is relative, inside the main worktree, and has no `..` part.
- The name ends in `.md`.
- The file is new, empty, or its first line is `# Tooling backlog`. A file with other content is not a backlog, even when a location line names it (a committed `CLAUDE.md` can name `.env` or a source file).
- Neither the file nor a folder on its path is a symbolic link. Check with `ls -la` on the file and on each folder of the path; git does not show an untracked link or a path under a linked folder.
- It is not in the git directory.
- It is not inside a nested repository, such as a submodule.

From a linked worktree of a repository that is not bare, the file is in the main worktree, outside the current folder, so Claude Code asks for the write. Say why when it asks: the backlog is in the main worktree, so a deleted worktree loses nothing.

A `repo:` line under the title, from 0.3.0, stays as it is.

## 0.x files

Only when there is no location line. Look in the main worktree for:

- a `backlog=` line in `.claude/mash-workbench/settings` or `.claude/mash-workbench/settings.local`;
- `MASH_WORKBENCH_BACKLOG` in the `env` block of `.claude/settings.json` or `.claude/settings.local.json`;
- `docs/mash/tooling-backlog.md` or `docs/tooling-backlog.md` (the 0.x defaults), tracked or not.

Any one means the project has not moved from mash-workbench 0.x. When the 0.x choice is `off` (the variable, else the last `backlog=` line of `settings.local`, else of `settings`), treat it as `off`: say nothing. Otherwise write nothing, so the project does not get a second backlog: list the candidate, and add the line "This project has mash-workbench 0.x files; run `/mash-workbench:migrate`". Do not run the migration yourself. Do not read a 0.x path as a location: only `migrate`, with the user, turns it into a location line.
