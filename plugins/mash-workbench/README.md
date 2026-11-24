# mash-workbench

A Claude Code plugin (other coding assistants, GitHub Copilot CLI first, are planned but not supported yet) that turns repeated work into tooling. During a session Claude notes each thing worth automating as a line in your repo's backlog; later `/forge` proposes what to build, in the most deterministic form that fits, and builds only what you approve.

It is made of instructions only: three skills. It has no hook, no script and no settings file, so it needs no Python and asks for no allow rules. The design, with diagrams, is in [docs/specs/mash-workbench.md](../../docs/specs/mash-workbench.md); the reasons are in [ADR 0008](../../docs/decisions/0008-mash-workbench-instructions-only.md).

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/mash-workbench`.

**Coming from 0.x?** Run `/mash-workbench:migrate` in each project that used it, and remove the old allow rule: the 1.0.0 entry of [CHANGELOG.md](CHANGELOG.md) says how. Until you do, `scout` writes nothing in that project, `forge` reads no backlog there, and both point to `migrate`.

## The loop

1. **Capture**: the `scout` skill fires when Claude repeats a multi-step procedure, when you correct the same thing twice, when a manual check could be automated, or when a memory it is about to save describes a procedure. It appends one line to the project's tooling backlog and returns to the task:

   ```
   - [ ] 2026-10-14 · script · Check the lockfile matches CI's Python version — CI failed twice on a version the lockfile didn't pin
   ```

   Each line records the date, a proposed form, a title, and **why** the candidate exists. Commit the file with the repo, so the reasons are reviewable and versioned. Every worktree writes to the main worktree's file, so a new line waits there as an uncommitted change; no skill commits it.

2. **Forge**: the `forge` skill (`/mash-workbench:forge`; plain `/forge` also works unless another command has that name) reads the open backlog entries, the current session, and the review escapes of the mash-review plugin, then shows one table: form, where the tool should live, reasoning, rough size, pros and cons, and a recommendation. You pick which to build. It builds each approved item test-first, ticks it off with a pointer to where it now lives, and turns a promoted memory into a one-line pointer so the rule lives in one place.

With no user present (`claude -p`, a background session) or in plan mode, `scout` writes nothing and lists the candidates under "Tooling candidates to record" in its final report, and `forge` gives its table and builds nothing.

## Where the backlog is

`docs/mash/tooling-backlog.md` in the main worktree, unless an instruction file of the main worktree names another one with a line:

```markdown
Tooling backlog: docs/tooling/backlog.md
```

`Tooling backlog: off` turns the backlog off. `scout` looks in `CLAUDE.md`, then `AGENTS.md`, then `.github/copilot-instructions.md`. The first time it has something to note and there is no backlog, it asks where to keep it, and writes the line only on your yes: in `CLAUDE.md`, or in `AGENTS.md` when the project has no `CLAUDE.md` (a new `CLAUDE.md` would stop Claude Code from loading `AGENTS.md`).

## Deterministic first

Each candidate is promoted to the most deterministic form that fits. This ladder is for the tooling `forge` builds in your project; the plugin itself is instructions only.

| Form   | Use for                                                | Pros                           | Cons                               |
| ------ | ------------------------------------------------------ | ------------------------------ | ---------------------------------- |
| hook   | a rule that must always hold (block, format, validate) | enforced every time, no tokens | only for checks a program can make |
| script | a procedure with no judgment                           | repeatable, testable, cheap    | someone must decide to run it      |
| skill  | judgment, with scripts for the mechanics               | flexible                       | Claude may skip or misread it      |
| agent  | a review that needs a separate context                 | fresh eyes, own model          | slow and costly                    |
| mcp    | access to an external system                           | reusable integration           | most to build and maintain         |

When the form is unclear at capture time, the entry says `unsure` and `/forge` decides. A mash-review escape topic becomes a **review standard**, built with mash-review's `add-standard` skill.

**Where it goes**: useful beyond this project → a plugin or config repository shared across projects; project-specific agent tooling → the project's own agent folder (`.claude/` in Claude Code); project domain logic → the project's own code.

## Requirements

Claude Code and `git`. Built for Claude Code and developed against 2.1.331; older versions are untested. Nothing needs a network.

## Optional integrations

- **mash-review** plugin: when the project keeps review escapes (one file per bug a review passed, in `.mash-review/escapes/` of the main worktree), `/forge` counts them per topic and proposes a review standard for a topic with three or more files.
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

## What it writes

The plugin has no hooks and no scripts, so nothing runs on its own and nothing runs outside the session. What the skills tell Claude to write:

- `scout`: one line in the backlog file, and the title line of a new backlog. Only a `.md` file inside the repository that is new, empty, or starts with `# Tooling backlog`; never through a symbolic link. A `Tooling backlog:` line in an instruction file, only on your yes.
- `forge`: `- [x]` marks in the backlog, and the tooling you approve. It reads the backlog only when the file passes the same checks.
- `migrate`: the items of its proposal that you approve: a location line, a moved backlog file, removed settings files, exclude lines and allow rules.

The permission prompt. In the default permission mode Claude Code asks you before each edit, and before a write outside the session's folder (from a linked worktree, the backlog is in the main worktree). In `acceptEdits`, auto or `bypassPermissions` mode, or with an allow rule for edits, it does not ask: then only the skill's own checks stand between a committed `Tooling backlog:` line and the file it names. A session with no user writes nothing.

Read the skills before you install: `skills/*/SKILL.md` and `reference.md`. A prompt you can paste into your own agent (the installed copy is in `~/.claude/plugins/cache/mash-workbench-marketplace/mash-workbench/<version>/`):

```
Review the Claude Code plugin in <folder>. Cover what each skill (SKILL.md, reference.md) tells the model to read, run or edit. List every file it can write, and say which writes can go outside the repository.
```

## Pin a version

An update changes the instructions Claude follows, so you may want to stay on a commit you have read. Add this marketplace at a commit by giving that commit's full SHA as the `ref` (the form `owner/repo@<sha>`, or the `ref` field of an `extraKnownMarketplaces` entry); this needs Claude Code 2.1.324 or later. See https://code.claude.com/docs/en/plugins/marketplace-reference.md. Each release has a section in `CHANGELOG.md`.

## Uninstall and support

`/plugin uninstall mash-workbench@mash-workbench-marketplace`. The backlog file and the `Tooling backlog:` line stay in your repositories; delete them if you do not want them. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
