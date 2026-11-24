# 0008: mash-workbench is made of instructions only

Status: accepted. It supersedes [0006](0006-scripts-trust-no-input.md) for mash-workbench. With [0007](0007-instructions-first.md), no plugin of this marketplace has scripts, so 0006 applies to no plugin.

## Context

mash-workbench 0.3.0 had eight scripts: 1,464 lines of bash and 380 lines of Python. The scripts wrote one line to a Markdown file, found that file, and read Claude Code transcripts. These problems occurred:

1. **Security.** The audit of 0006 found security bugs in the backlog scripts. The corrections added a settings file, a lock, path checks, git-directory checks and an old-copy check. Each check needs a test. Each new script needs the same checks. The expected result is a plugin that has no script that an allow rule can approve.
2. **Setup.** The first entry needed a setup question, a settings file and an allow rule. The allow rule names the version folder, so the user must replace it after each plugin update. The expected result is that the first entry needs one question at most.
3. **Python.** `past-friction.py` needs Python 3.11 or a later version. On a host with an earlier version, and on Windows with the Microsoft Store alias, `forge` skipped that source. The expected result is the same behavior on each host.
4. **Old integration.** `forge` ran `escapes-report.sh` of the old review plugin and counted `.claude/mash-workbench/escapes/`. mash-review 1.0.0 has no scripts and writes escapes to `.mash-review/escapes/`. As a result, `forge` found no escapes. The expected result is that `forge` reads the escapes of mash-review.
5. **Two rules.** `AGENTS.md` said "Instructions first", but mash-workbench kept its scripts. The expected result is one rule for each plugin.

## Decision

1. **Instructions only.** mash-workbench 1.0.0 contains three skills: `scout`, `forge` and `migrate`. It contains no hook, no script, no settings file and no allow rule. The name stays mash-workbench.
2. **The model writes the line.** `scout` appends the backlog line with the edit tool of the session. In the default permission mode, Claude Code asks the user before the write.
3. **The checks become instructions.** `scout` writes only to a `.md` file in the repository. The file must be new, empty, or have the first line `# Tooling backlog`. `scout` does not write through a symbolic link.
4. **An instruction file holds the location.** The default is `.mash-workbench/tooling-backlog.md` in the main worktree. This agrees with the folder `.mash-review/` of mash-review. The 0.x default `docs/mash/tooling-backlog.md` is a 0.x file. `migrate` moves it when the user agrees. A line `Tooling backlog: <path>` or `Tooling backlog: off` in `CLAUDE.md`, `AGENTS.md` or `.github/copilot-instructions.md` of the main worktree changes it. The skill writes that line only when the user agrees. It writes the line in `CLAUDE.md`, or in `AGENTS.md` when there is no `CLAUDE.md`.
5. **No user, no write.** When no user is present, `scout` and `forge` write nothing. The final report lists the candidates.
6. **No transcripts.** `past-friction.py` and `scripts/python.sh` are removed. `forge` uses the backlog, the current conversation and the escapes of mash-review.
7. **forge reads mash-review.** `forge` counts the escape files in `.mash-review/escapes/` by `topic:`. A topic with three or more files is a candidate for a review standard.
8. **migrate.** A `migrate` skill moves a project from 0.x when the user asks for it. When 0.x files exist, `scout` writes nothing and shows a hint, and `forge` shows the hint.

## Options that we did not select

- **Keep the scripts.** Pros: the checks of 0006 are deterministic. Cons: each check is code to keep and to test. The allow rule needs a change after each update.
- **Keep only `past-friction.py`.** Pros: `forge` keeps leads from earlier sessions. Cons: the plugin keeps Python, `python.sh`, the rules of 0006 and their tests for one source. The script reads private transcripts.
- **Read the transcripts with an instruction.** Pros: no script. Cons: a read outside the project needs approval. The model reads large files, and the output can show private text.
- **Keep the settings file.** Pros: no change for projects that use it. Cons: the model must read a format that only this plugin uses. A committed settings file can select a place outside the repository, which needs checks.
- **Only CHANGELOG steps for migration.** Pros: no third skill. Cons: a project with a custom backlog path loses it with no message. The old allow rule stays when the user does not read the CHANGELOG.

## Pros and cons

- Pros: the plugin works on each host that runs Claude Code, with no Python and no allow rule.
- Pros: there is no script, so there is no script attack surface and no security check to keep.
- Pros: the first entry needs one question at most, and the default needs no line in a file.
- Cons: the model must do the checks on the backlog file. The permission prompt is the only other guard. In `acceptEdits`, auto and `bypassPermissions` mode, and with an allow rule for edits, Claude Code does not ask for an edit in the project. Then only the instruction remains.
- Cons: a session with no user present cannot write an entry. A later session with a user must record the listed candidates.
- Cons: `forge` loses the leads from earlier sessions.
- Cons: a project that used 0.x runs `migrate` once.
- Cons: the plugin's behavior has no bash tests. `claude plugin eval` cases and manual runs replace them, and they cost model calls.
