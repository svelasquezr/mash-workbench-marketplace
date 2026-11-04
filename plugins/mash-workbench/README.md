# mash-workbench

A Claude Code plugin (other coding assistants, GitHub Copilot CLI first, are planned but not supported yet) that turns repeated work into tooling. During a session Claude notes each thing worth automating as a line in your repo's backlog; later `/forge` proposes what to build, in the most deterministic form that fits, and builds only what you approve.

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/mash-workbench`.

## The loop

1. **Capture**: the `scout` skill fires when Claude repeats a multi-step procedure, when you correct the same thing twice, when a manual check could be automated, or when a memory it is about to save describes a procedure. It appends one line to the project's tooling backlog (`docs/mash/tooling-backlog.md` unless you chose another file; the first time, it asks) and returns to the task:

   ```
   - [ ] 2026-10-14 · script · Check the lockfile matches CI's Python version — CI failed twice on a version the lockfile didn't pin
   ```

   Each line records the date, a proposed form, a title, and **why** the candidate exists. The file is committed with the repo, so the reasons are reviewable and versioned.

2. **Forge**: the `forge` skill (`/mash-workbench:forge`; Claude Code's docs say plain `/forge` also works unless another command has that name) reads the open backlog items, the current session, and corrections you repeated in the project's earlier sessions (three `grep` commands over Claude Code's prompt history, shown in the skill's reference), then shows one table: form, where the tool should live, reasoning, rough size, pros and cons, and a recommendation. You pick which to build. It builds each approved item test-first, ticks it off with a pointer to where it now lives, and turns a promoted memory into a one-line pointer so the rule lives in one place.

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

- `git` and `grep`. The plugin ships no scripts: only two skills, which tell Claude which commands to run.
- Built for Claude Code and developed against 2.1.318; older versions are untested.
- `scout` writes only the project's tooling backlog, and only once you chose where it lives: the first time it has something to note, it asks whether to create `docs/mash/tooling-backlog.md`, use another file, or keep none; a backlog already at `docs/tooling-backlog.md` keeps working where it is (move it with `git mv` when you like), and when it creates the file it offers to add it to `.gitignore` (an ignored backlog holds only your entries; committing it is the default and shares them). To answer once for later sessions, set `MASH_WORKBENCH_BACKLOG` (a path relative to the repository, or `off`) in the `env` block of `.claude/settings.local.json` (only you) or `.claude/settings.json` (everyone). `forge` writes only what you approve it to build.
- For earlier sessions, `forge` reads Claude Code's prompt history (`~/.claude/history.jsonl`, or `$CLAUDE_CONFIG_DIR/history.jsonl`) through one pipeline of three `grep` commands: it keeps this project's lines, then the prompts that read like a correction ("no, …", "I told you", "you keep", "… again"), then prints only the prompt text and its session id. Pasted contents and other projects' prompts never reach Claude. It makes no network call and writes nothing; `forge` summarises what recurs in two or more sessions and never copies your prompts into the table, the backlog or any file. The exact command is in `skills/forge/reference.md`; run it yourself to see what `forge` is shown. Other tools have no such file, and `forge` skips this source there.

## Optional integrations

- **review-routing** plugin: when the project keeps a review-escape ledger (`docs/mash/review-escapes.md`), `/forge` counts bugs reviews missed per area and proposes a specialist reviewer for an area with two or more.
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

## Upgrading from 0.2

The plugin no longer ships `backlog-add.sh`, `backlog-path.sh`, `backlog-stale.sh` or `past-friction.py`, and no longer needs Python. The backlog format and `MASH_WORKBENCH_BACKLOG` are unchanged. Earlier sessions now come from the prompt history instead of the full transcripts, so repeated command sequences are no longer listed; repeated corrections are.

## Uninstall and support

`/plugin uninstall mash-workbench@mash-workbench-marketplace`. The backlog file stays in your repositories; delete it if you do not want it. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
