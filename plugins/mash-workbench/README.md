# mash-workbench

A Claude Code plugin (other coding assistants, GitHub Copilot CLI first, are planned but not supported yet) that turns repeated work into tooling. During a session Claude notes each thing worth automating as a line in your repo's backlog; later `/forge` proposes what to build, in the most deterministic form that fits, and builds only what you approve.

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/mash-workbench`.

## The loop

1. **Capture**: the `scout` skill fires when Claude repeats a multi-step procedure, when you correct the same thing twice, when a manual check could be automated, or when a memory it is about to save describes a procedure. It appends one line to the project's tooling backlog (`docs/mash/tooling-backlog.md` in the main worktree unless you chose another file; the first time, it asks) and returns to the task:

   ```
   - [ ] 2026-10-14 · script · Check the lockfile matches CI's Python version — CI failed twice on a version the lockfile didn't pin
   ```

   Each line records the date, a proposed form, a title, and **why** the candidate exists. Commit the file with the repo, so the reasons are reviewable and versioned. Every worktree writes to the main worktree's file, so a new line waits there as an uncommitted change; no skill commits it.

2. **Forge**: the `forge` skill (`/mash-workbench:forge`; Claude Code's docs say plain `/forge` also works unless another command has that name) reads the open backlog items, the current session, and recurring corrections and command sequences from the project's earlier sessions (`scripts/past-friction.py`, read-only, no model call), then shows one table: form, where the tool should live, reasoning, rough size, pros and cons, and a recommendation. You pick which to build. It builds each approved item test-first, ticks it off with a pointer to where it now lives, and turns a promoted memory into a one-line pointer so the rule lives in one place.

## Deterministic first

Each candidate is promoted to the most deterministic form that fits:

| Form   | Use for                                                | Pros                           | Cons                               |
| ------ | ------------------------------------------------------ | ------------------------------ | ---------------------------------- |
| hook   | a rule that must always hold (block, format, validate) | enforced every time, no tokens | only for checks a program can make |
| script | a procedure with no judgment                           | repeatable, testable, cheap    | someone must decide to run it      |
| skill  | judgment, with scripts for the mechanics               | flexible                       | Claude may skip or misread it      |
| agent  | a review that needs a separate context                 | fresh eyes, own model          | slow and costly                    |
| mcp    | access to an external system                           | reusable integration           | most to build and maintain         |

When the form is unclear at capture time, the entry says `unsure` and `/forge` decides.

**Where it goes**: useful beyond this project → a plugin or config repository shared across projects; project-specific agent tooling → the project's own agent folder (`.claude/` in Claude Code); project domain logic → the project's own code.

## Requirements and what it reads

- `git` and `bash`; for `past-friction.py` also Python 3.11 or newer, found as `python3`, `python` or the Windows launcher `py -3` (the Microsoft Store alias does not count; set `MASH_PYTHON` to choose one: a command such as `py -3.12`, or a full path to the interpreter, which may hold spaces but then takes no arguments). The backlog scripts need only `bash`. The Python script uses the standard library only, and nothing needs a network.
- Built for Claude Code and developed against 2.1.289; older versions are untested.
- `scout` writes only the project's tooling backlog, and only once you chose where it lives: the first time it has something to note, it asks whether to keep `docs/mash/tooling-backlog.md` (committed, the default), another file, or none, and saves the answer as the `backlog` setting in `.claude/mash-workbench/settings` (for the team; commit it) or `settings.local` (only you). A backlog that already exists at `docs/mash/tooling-backlog.md` or `docs/tooling-backlog.md` keeps working where it is; the skill asks once whether to keep it there or move it, and records the answer. `MASH_WORKBENCH_BACKLOG` in your environment (a path, or `off`) still wins over both files. "Audit this plugin" says who can choose a file outside the repository. `forge` writes only what you approve it to build.
- `scripts/past-friction.py` reads your Claude Code session transcripts for the current project (`~/.claude/projects/<project-folder>/*.jsonl`, and the folders of its worktrees) to find corrections and command sequences that recur across sessions. It makes no model call and no network call, never writes to the transcripts, and prints only counts, dates and one example per pattern. A correction's example shows only the wording that two or more sessions share; every other word is replaced by "…", so something you typed once (a name, a path, a secret) is not printed, though a phrase you repeat across sessions would be. A command sequence shows only program, subcommand and script names. It does not follow symbolic links out of the transcripts folder, and uses `$CLAUDE_CONFIG_DIR/projects` when that is set. Run it yourself first if you want to see exactly what `forge` is shown: `bash plugins/mash-workbench/scripts/python.sh plugins/mash-workbench/scripts/past-friction.py --project <path>`.

## Optional integrations

- **review-routing** plugin: when the project keeps review escapes (one file per bug a review passed, in `.claude/mash-workbench/escapes/` by default), `/forge` counts them per area and proposes a specialist reviewer for an area that reached the escape threshold (default 3).
- **superpowers** plugin: new skills follow its `writing-skills` method when installed.

Neither is required.

## How it compares

Summaries of each project as of October 2026; check the project itself for what it does today.

| Tool                                                                                               | What it does                                                        | Difference from mash-workbench                                                                                                                     |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| [claude-reflect](https://github.com/BayramAnnakov/claude-reflect)                                  | hooks queue your corrections; `/reflect` applies them with approval | writes mostly prose rules (CLAUDE.md); `/reflect-skills` also turns repeated workflows from past sessions into commands; no hooks or scripts       |
| [hookify](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/hookify)         | turns an instruction or correction into a warn/block rule           | pattern-matching rules (regex, contains, equals), no backlog; a good fit for quick personal rules, while mash-workbench builds tested hook scripts |
| [Claudeception](https://github.com/blader/Claudeception)                                           | extracts skills from sessions                                       | skills only, no triage                                                                                                                             |
| continuous-learning ([everything-claude-code](https://github.com/affaan-m/everything-claude-code)) | hooks record observations, `/evolve` clusters them                  | promotes to skills and agents, not hooks or scripts; mostly automatic                                                                              |
| Claude Code `/insights`                                                                            | report of friction over recent sessions                             | a report; you act on it by hand                                                                                                                    |

mash-workbench's difference: one backlog with a reason per entry, a deterministic-first ladder across five forms, a place to put each tool, your approval before anything is built, and test-first building.

## Audit this plugin

You can read every script before you run it. This section says what each one reads and writes, so you know what to look for. The decisions behind it are in `docs/decisions/0005` and `0006` of the marketplace repository. The plugin has no hooks, so nothing runs on its own.

Network. None of the scripts is written to make a network call. `tests/test_no_network.sh` in the marketplace repository is a tripwire for that, not proof. It scans every file under `plugins/` that git tracks or would track, except `README.md`, `CHANGELOG.md` and `LICENSE`, and fails when one contains a word from a fixed list: network tools and libraries (for example `curl`, `wget`, `urllib`, `socket`, `ssh`, `rsync`), tools that download code (`npx`, `uvx`, `pip install`), any `gh` command, and `git` with a subcommand that talks to a remote (`push`, `fetch`, `pull`, `clone`, `ls-remote`), also with options or variables before the subcommand and in the quoted list form Python uses. It also fails on a file that is not text, such as a compiled `.pyc`. The matches it accepts are listed in `tests/no_network_allowed.txt`, each with its file, line and reason. In this plugin they are a comment about remote URLs in `mash-settings.sh`, and two lines of `past-friction.py`: a docstring example, and the list of program names it recognizes in transcripts (`git`, `gh`, `npx`, `uvx` and others; it runs none of them). A script can reach a network in a way that is not on the list, so read the scripts too.

Writes. `tests/test_write_scope.sh` runs `backlog-add.sh`, `backlog-stale.sh`, `permission-rules.sh`, `past-friction.py` and `mash-settings.sh` from a private copy of the plugin against throwaway repositories. Before and after each run it lists four folders: the folder that holds the repositories, a fresh home folder, a private `$TMPDIR`, and the plugin copy. It fails when a path changed that is not in the table below, and when a script that should only read changed anything. It does not watch any other folder, so a write to a fixed path elsewhere (under `/var/tmp`, or in your real home folder) would pass: it catches the common mistakes and is not proof either. The cases where a script must refuse to write are in `tests/test_backlog_add.sh` and `tests/test_mash_settings.sh`.

| Script                             | Reads                                                                                                                                                                                                                     | Writes                                                                                                                                                                                                                     | Network |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `skills/scout/backlog-add.sh`      | the backlog file, the settings, `git remote get-url origin`; no file that an argument names                                                                                                                               | the tooling backlog file only, and the folder that holds it when it is new; when it adds the `repo:` line to an old file, a short-lived copy next to the file                                                              | none    |
| `skills/scout/backlog-path.sh`     | the settings (`MASH_WORKBENCH_BACKLOG`, then `settings.local`, then `settings`), and whether the old default files exist                                                                                                  | nothing                                                                                                                                                                                                                    | none    |
| `skills/scout/backlog-stale.sh`    | the backlog file                                                                                                                                                                                                          | nothing; plain bash, no Python                                                                                                                                                                                             | none    |
| `skills/scout/permission-rules.sh` | the `Bash(...)` strings in the lists of `.claude/settings.local.json` in the main worktree and in the current linked worktree, and `git worktree list`                                                                    | nothing; it only prints the rule                                                                                                                                                                                           | none    |
| `scripts/past-friction.py`         | your Claude Code session transcripts for this project, in `$CLAUDE_CONFIG_DIR/projects` or `~/.claude/projects`, including the folders of the project's worktrees                                                         | nothing; it prints counts, dates, wording that two or more sessions share, and the program, subcommand and script names of command sequences                                                                               | none    |
| `scripts/mash-settings.sh`         | the settings files in the main worktree's `.claude/mash-workbench/`; `MASH_WORKBENCH_BACKLOG` and `REVIEW_ROUTING_ESCAPES`; the backlog file's `repo:` line; the origin URL, the worktree list, tracked and ignored paths | `settings`, `settings.local`, the lock folder `.settings.lock` and a short-lived `.settings.<pid>.tmp` in `.claude/mash-workbench/`, and `info/exclude` for `set --local`; only when you run `set` or `unset` (setup does) | none    |
| `scripts/plugin-current.sh`        | `installed_plugins.json` next to Claude Code's plugin cache, when the plugin is installed there; the top folder and the main worktree of the current folder through `mash-settings.sh`                                    | nothing                                                                                                                                                                                                                    | none    |
| `scripts/python.sh`                | `MASH_PYTHON`: when it is set, the file runs it as the interpreter (one path when it holds `/` or `\`, else split into words)                                                                                             | nothing; it runs that interpreter, else the first Python 3.11 or newer it finds, isolated (`-I -B`): no module from the current folder or `PYTHONPATH`, no `__pycache__`                                                   | none    |

Where the backlog is. The file is `docs/mash/tooling-backlog.md` in the main worktree unless a setting names another one. `MASH_WORKBENCH_BACKLOG` in the environment wins, then `.claude/mash-workbench/settings.local` (only you), then the committed `.claude/mash-workbench/settings`. A file inside the repository can come from any of the three. A file outside the repository is accepted only from `settings.local` or the environment variable, which are yours: when the committed `settings` file names one, the scripts stop (exit 6) and the session asks you. `settings.local` counts as yours only when git answers that the main repository's index does not track it, and the line `.claude/mash-workbench/settings.local` is in the repository's `info/exclude` (`mash-settings.sh set ... --local` writes it; a commit, a patch or a clone cannot): a repository can commit one, or a patch applied with `git apply` can create one, and the scripts then read it as a committed file. The line stays when you delete the file, so after your first `set --local` a file that a patch creates counts as yours. The scripts name the git directory and the work folder in that question, so git looks for no repository inside `.claude`; a git error counts as tracked. A submodule or a nested repository at `.claude` or `.claude/mash-workbench` is refused (exit 6). Git starts only in a repository that a real `.git` entry names: a folder shaped like a git directory (it holds `HEAD` and `objects/` or `refs/`, which a commit can hold) is refused with exit 6 before any git runs, because git would read its committed config, and that config can name a program to run. This also refuses a bare repository's own folder; its linked worktrees work as before. `.claude` and `.claude/mash-workbench` must be real folders: a symbolic link there is refused, also one that stays inside the repository. A settings file that is a symbolic link is refused, and so is a path with a backslash. The scripts also refuse a linked worktree, a temporary folder, the git directory, a file whose `repo:` line names another repository, and a symbolic link (the file itself, a folder on its path that leads out of the repository, or `.claude/mash-workbench`). No argument of `backlog-add.sh` names the file: `--create` and `--file` are gone since 0.3.0. The script writes only to a new file, an empty `.md` file, or a file whose first line is `# Tooling backlog`: a committed setting such as `backlog=.env` gets exit 6, not a line in that file. When you chose a file outside the repository, that is where the script writes. The environment variable has your trust: the `env` block of a committed `.claude/settings.json` can set it, as it can set `MASH_PYTHON`, but Claude Code applies that file only after you accept its workspace-trust dialog.

The permission prompt. Claude Code asks you before it runs a Bash command, with these exceptions: a command an allow rule covers, a command Claude Code counts as read-only, a sandboxed command when `autoAllowBashIfSandboxed` is on, and every command in auto or bypass mode. A `claude -p` session has nobody to ask, so a command that needs approval is refused there. Where the prompt appears, it is your main control: you can read the script before you say yes.

The optional allow rule. When setup asks where the backlog lives, it also offers one allow rule, for `backlog-add.sh`, so a background session in a new worktree can note a candidate without a prompt. `permission-rules.sh` prints it: `Bash(bash <installed path>/skills/scout/backlog-add.sh *)`, the exact installed path and one wildcard, at the end, for the arguments. Setup adds it to `permissions.allow` in `<main worktree>/.claude/settings.local.json`, and only when you say yes. If your project commits that file, do not accept the rule: it holds an absolute path of your machine. No rule is offered when the plugin folder is inside the repository, or when its path holds a character a rule cannot spell safely.

After a plugin update. The rule names the plugin's version folder, so it does not match the new version's script. But Claude Code keeps the old version's folder in its plugin cache, and the old rule still matches the old script there. So after each update, run setup step 3 again (the `scout` reference describes it): `permission-rules.sh` lists the old rule as a `remove:` line and offers no new rule until it is gone. It reads only the main worktree's `.claude/settings.local.json` and the current linked worktree's. There is a second guard: `backlog-add.sh` asks `scripts/plugin-current.sh` first, and a copy in the plugin cache that `installed_plugins.json` no longer lists, for you or for the project of the current folder, stops with exit 6 and writes nothing.

What the rule still pre-approves, and the other limits:

- Any arguments to `backlog-add.sh` at that one path: any title and reason, as one line in the backlog file.
- `<repo-root>` is an argument, but `backlog-add.sh` refuses one that is not in the repository of the session's current folder (exit 6), and Claude Code blocks a `cd` out of the session's folders. No rule is offered on Windows (Git Bash, MSYS, Cygwin), where the checks are not tested; CI tests Linux and macOS. Outside a git repository the current folder must be inside `<repo-root>` and outside every git repository, and there are no settings files and no path checks: there, `MASH_WORKBENCH_BACKLOG` (or an old `docs/mash/tooling-backlog.md` or `docs/tooling-backlog.md`) and the folder given as `<repo-root>` decide, and the script only refuses a symbolic link that would move the write out of that folder.
- A rule allows a path, not content. Anyone, or any program, that can write to the installed plugin folder changes what runs with no prompt.
- The rule matching was tested on Claude Code 2.1.330 only, and `plugin-current.sh` knows the cache layout of that version; with another layout, an empty registry or one cut in the middle of a write, it cannot tell: it says so in one line on stderr and lets the copy run.

If one of these matters to you, do not accept the rule and approve each call.

Python. Only `past-friction.py` needs Python 3.11 or newer. Without it, `/forge` says it skipped earlier sessions and goes on with the other sources. The backlog scripts need only `bash`.

Sandbox users. The Claude Code sandbox is off by default. When it is on, a script can write only inside the session's folder, any folder added with `--add-dir` or `permissions.additionalDirectories`, and the per-user `$TMPDIR`, unless `sandbox.filesystem.allowWrite` names another folder; a session in a linked worktree writes into that worktree. The backlog is in the main worktree, so from a linked worktree `sandbox.filesystem.allowWrite` must name its folder, and on Linux and WSL2 the folder must exist first, because the documentation says an entry for a path that does not exist yet has no effect. `sandbox.enabled` turns the sandbox on, and `sandbox.autoAllowBashIfSandboxed` removes the prompt for commands that run inside it (it does not grant any write). Inside a container you also need `enableWeakerNestedSandbox`. A file in the repository cannot set `autoAllowBashIfSandboxed`, so set these in your own settings. See https://code.claude.com/docs/en/sandboxing.

A prompt you can paste into your own agent. The installed copy is in `~/.claude/plugins/cache/mash-workbench-marketplace/mash-workbench/<version>/`; in a clone of the marketplace it is `plugins/mash-workbench`.

```
Review the Claude Code plugin in <folder> for network access, writes outside the repository, command injection and unsafe file handling. Cover the scripts and what each skill (SKILL.md, reference.md) tells the model to run or edit. List every finding with file and line. Say which writes go outside the repository, and to which paths.
```

## Pin a version

An update changes the scripts that run on your machine, so you may want to stay on a commit you have read. This section follows the Claude Code documentation at https://code.claude.com/docs/en/plugins/marketplace-reference.md. The `owner/repo@<sha>` form was run once, on Claude Code 2.1.330: `claude plugin marketplace add svelasquezr/mash-workbench-marketplace@<full 40-character SHA>` cloned that commit, `/plugin marketplace list` showed the SHA, and the installed plugin recorded it as `gitCommitSha` in `installed_plugins.json`. The rest was not run.

The documented pin for you, as a user, is the marketplace `ref`: add this marketplace at a commit by giving that commit's full SHA as the `ref` (the form `owner/repo@ref`, or the `ref` field of an `extraKnownMarketplaces` entry). This needs Claude Code 2.1.324 or later. The `ref` and `sha` fields of a plugin source are set by the marketplace author, and the entries in this marketplace are relative paths, so you do not set them.

The documentation names no `plugin install name@version` form: in `mash-workbench@mash-workbench-marketplace`, the part after `@` is the marketplace, not a version. To check what is installed, run `/plugin marketplace list` and `/plugin`. The documentation does not say whether a marketplace pinned this way still updates by itself, so check after the first update. Each release has a section in `CHANGELOG.md` with the scripts whose behavior changed, so you can see what to re-read before you move to a new commit.

## Uninstall and support

`/plugin uninstall mash-workbench@mash-workbench-marketplace`. The backlog file stays in your repositories; delete it if you do not want it. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
