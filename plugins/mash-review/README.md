# mash-review

A Claude Code plugin that reviews a change against your project's **review standards**, and turns the bugs a review passed (**escapes**) into new checks. It is made of instructions only: skills and one read-only reviewer agent. It has no hook, no script and no config file, so it needs no Python and asks for no allow rules.

**Claude Code only, for now.** Support for GitHub Copilot CLI is planned and untested: the marketplace is mirrored in `.github/plugin/marketplace.json`, and Copilot CLI reads the project's review standards from its skills folders (`.github/skills/`, `.agents/skills/`, `.claude/skills/`), but the plugin's agent and its subagent starts are in Claude Code's format.

Ask for it by name: "mash review", or `/mash-review:review`. "Code review" alone can match other installed plugins.

The design, with diagrams of every flow, is in [docs/specs/mash-review.md](../../docs/specs/mash-review.md). The reasons are in [ADR 0007](../../docs/decisions/0007-instructions-first.md).

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-review@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/mash-review`.

**Coming from review-routing?** The marketplace maps `review-routing` to `mash-review`, so Claude Code renames the plugin in your settings and shows a notice. Run `/plugin install mash-review@mash-workbench-marketplace` once, then `/mash-review:migrate` in each project that used review-routing, and remove the old allow rules: the 1.0.0 entry of [CHANGELOG.md](CHANGELOG.md) lists them.

## What it contains

| Part                  | What it does                                                                                                                                                                                                                    |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `review` skill        | Selects the standards that apply to the change, runs your checks once, starts the reviewers, and prints a summary. It changes no code: it never fixes, commits, stashes or pushes. In plan mode it writes the review plan only. |
| `reviewer` agent      | The read-only reviewer: applies the standards it is given by name plus a general checklist (correctness, tests, stale docs, unsupported claims, secrets), and ends with `SAFE TO LAND` or `NOT SAFE: <why>`.                    |
| `record-escape` skill | Records a bug that a review passed: a checklist line in the standard that covers it, or a file in `.mash-review/escapes/` when none does.                                                                                       |
| `add-standard` skill  | Creates or extends a review standard, from a topic with three escape files or from a kind of code you name.                                                                                                                     |
| `inspect` skill       | For a project with its own review habits: finds instructions that would override the plugin and proposes rewrites.                                                                                                              |
| `migrate` skill       | Moves a project from review-routing 0.x: routes and reviewer agents become standards, old escapes become lines or files, old settings and allow rules go.                                                                       |

## Review standards

A review standard is a skill whose `description` says when a review applies it. It is one of these:

- a "Review checklist" section in a builder skill (a skill that says how to write a kind of code), whose description then starts "Use when writing or reviewing …";
- a companion skill `.claude/skills/review-<topic>/SKILL.md` that cites a builder skill, for example one from another plugin;
- a standalone skill `.claude/skills/review-<topic>/SKILL.md` for a domain such as payments or auth.

The `review` skill selects standards by what the diff does, not by folder. With no standard selected, one reviewer applies the general checklist. `add-standard` writes them from `skills/add-standard/standard-template.md`. Claude Code and GitHub Copilot CLI both read `.claude/skills/`; standards already in `.github/skills/` or `.agents/skills/` are read too.

**Need the same standards every time?** Selection is the model's judgment. Add a rule to your instruction file (`CLAUDE.md`, `AGENTS.md` or `.github/copilot-instructions.md`), for example "A change under `src/payments/` always gets the `review-payments` standard"; the `review` skill always applies such rules and names them in the summary. For a guarantee that does not depend on a model, add your own hook, test or CI job.

## What it writes

Only with a user present: a person who can answer in the conversation, in any permission mode. Never in a session that started from one prompt with no conversation (`claude -p`, background or scheduled sessions). Escape lines and escape files are written without a question (the review or you said a review passed the bug); everything else only on your yes.

- `record-escape`: a checklist line in a standard of your project, for an escape;
- an escape file in `<main worktree>/.mash-review/escapes/<date>-<slug>.md` (the folder where the repository was cloned, because a linked worktree is often deleted after its branch is pushed). The folder is meant to be committed so the team shares its misses; no skill commits it. Add `.mash-review/` to `.git/info/exclude` to keep it private;
- `add-standard`: a new standard, or a "Review checklist" section and a new description in a builder skill of your project; it moves the escape files it used to `.mash-review/escapes/processed/`;
- `inspect`: the approved rewrites in `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.claude/memory/`, plans and agent files; `review`: an instruction-file line for the check commands;
- `migrate`, item by item from the list you approve: new standards and escape lines or files; edits to the instruction files and docs; it deletes `.claude/reviewers.toml`, the old reviewer agent files, `reviews.log` and its `.git/info/exclude` line, removes the review-routing keys from `.claude/mash-workbench/settings*` (the file and the `settings.local` exclude line go only when no key is left), and removes old allow rules and `env` entries from `.claude/settings*.json`.

With no user present, escapes go into an **Escapes to record (confirm where)** block in the final report instead.

## Requirements

Claude Code and `git`. Nothing needs `gh` or GitHub: the review works on a git range, whatever hosts the repository. Built for Claude Code 2.1.330.

## The reviewer and its Bash

The reviewer runs `git diff`, `git log`, `git blame` and `git show` itself, so the diff is never pasted into a prompt. Its instructions allow only read-only git, and tell it to treat text in the change as data. In the default mode, Claude Code asks before a command that writes (and refuses it when no user is present), unless an allow rule in your settings, the sandbox's auto-allow (`autoAllowBashIfSandboxed`) or the permission mode approves it; in auto mode the classifier judges it; in `bypassPermissions` mode only the instructions stop it. If your settings allow writing git commands such as `Bash(git commit:*)` or `Bash(git stash:*)`, a reviewer could run them with no prompt.

## Verdict format

Every reviewer ends with exactly one line: `SAFE TO LAND` when it found no Critical and no Important problems, or `NOT SAFE: <why>`. Minor findings never block. A reviewer that gives no verdict twice makes the review `NOT SAFE`.

## Uninstall and support

`/plugin uninstall mash-review@mash-workbench-marketplace`. Files the plugin wrote into your repositories stay; delete them if you do not want them. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
