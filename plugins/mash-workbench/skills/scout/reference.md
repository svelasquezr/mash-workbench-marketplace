# scout reference

The design, with diagrams, is `docs/specs/mash-workbench.md` in the marketplace repository.

## First time

There is no location line and no `docs/mash/tooling-backlog.md`. Ask the user once, in one question, with a recommendation:

- `docs/mash/tooling-backlog.md`, committed (recommended: the whole team's candidates add up, and the reasons are reviewable). It needs no line: go on with "The file".
- Another file in the repository. Propose the line `Tooling backlog: <path>` ("Where the line goes" below), and write it only on a yes.
- None. Propose the line `Tooling backlog: off`, and write it only on a yes. Then write nothing.

A no to the line: use the answer for this session only; a later session asks again.

## Where the line goes

The line goes to `CLAUDE.md` when it exists; else to `AGENTS.md` when it exists (Claude Code reads `AGENTS.md` only where there is no `CLAUDE.md`, and a new `CLAUDE.md` would hide it); else to a new `CLAUDE.md`. Copilot CLI reads `.github/copilot-instructions.md` and `AGENTS.md`; when the project uses Copilot CLI, offer the same line there too.

## The file

Write to the backlog only when every answer is yes:

- The path is relative, inside the main worktree, and has no `..` part.
- The name ends in `.md`.
- The file is new, empty, or its first line is `# Tooling backlog`. A file with other content is not a backlog, even when a location line names it (a committed `CLAUDE.md` can name `.env` or a source file).
- Neither the file nor a folder on its path is a symbolic link. Check with `ls -la` on the file and each folder on the path, or `git ls-files -s <path>` (mode `120000` is a link).
- It is not in the git directory.
- It is not inside a nested repository, such as a submodule.

From a linked worktree, the file is in the main worktree, outside the current folder, so Claude Code asks for the write. Say why when it asks: the backlog is in the main worktree, so a deleted worktree loses nothing.

A `repo:` line under the title, from 0.3.0, stays as it is.

## 0.x files

Only when there is no location line. Look in the main worktree for:

- a `backlog=` line in `.claude/mash-workbench/settings` or `.claude/mash-workbench/settings.local`;
- `docs/tooling-backlog.md`.

Either one means the project has not moved from mash-workbench 0.x. Write nothing, so the project does not get a second backlog: list the candidate, and add the line "This project has mash-workbench 0.x files; run `/mash-workbench:migrate`". Do not run the migration yourself. Do not read the path in a settings file as a location: only `migrate`, with the user, turns it into a location line.
