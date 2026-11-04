# 0004. Plugins ship no scripts

## Status

Accepted (2026-11-04). Supersedes the "skills call scripts for mechanics" rule in `AGENTS.md`.

## Context

Consumers pushed back on the bash and Python files the plugins delivered: about 1,300 lines of Python routing in review-routing, two Python hooks, a transcript miner and seven bash helpers, all needing `python3` 3.11 or newer on every machine that installed a plugin. Code that runs on someone else's machine has to be read and trusted, and most of it was there only to make results repeatable.

The goal was to drop the scripts and keep the results deterministic.

## Decision

1. **Plugins ship only Markdown, JSON and TOML** (plus `LICENSE`). `tests/test_no_scripts.sh` enforces it: allowed file types, nothing executable, no shebang, no text that runs a file the plugin ships, no MCP servers, no hidden Unicode, and links only to github.com and code.claude.com.
2. **One exception: an inline hook.** `plugins/review-routing/hooks/hooks.json` holds one `PreToolUse` command, a line of POSIX shell and `grep` that denies a reviewer agent started on Haiku. It reads only the hook input, names no file and fails open. The owner approved it because a model cannot be forbidden to a subagent declaratively: the Agent tool's `model` overrides the agent file, and a plugin cannot ship permission rules.
3. **Git does the exact work.** Skills give Claude plain git commands instead of a program: glob pathspecs for routes (`git --glob-pathspecs diff --name-only`), exclude pathspecs for the default reviewer, `git diff -G` for changed lines, commit subjects and `--shortstat` for model rules, and a throwaway index (`GIT_INDEX_FILE`) so routing test cases can name paths that don't exist. One command per Bash call, so narrow permission rules allow them.
4. **Tool lists replace guards.** Reviewer agents get `tools: Read, Grep, Glob`. The caller writes the diff to a file under the git directory. A reviewer with no shell cannot change a checkout, write to GitHub or send data, whatever a reviewed change asks of it. This replaces an 829-line command parser that had known gaps.
5. **Determinism is checked by repo tests that run the documented commands**, not by evals: `tests/test_reviewers_config.sh` runs the routing and expect recipe on real configs, `tests/test_forge_history_recipe.sh` runs forge's history pipeline verbatim from its reference, and `tests/test_haiku_reviewer_guard.sh` runs the inline hook on hook input. What remains is the model chaining those commands: verified by hand with headless `claude -p --plugin-dir` runs on a scratch repository.
6. **A plugin-safety reviewer** (`.claude/agents/plugin-safety-reviewer.md`, routed through this repository's `.claude/reviewers.toml`) judges what the test can't: disguised scripts, unsafe or malicious instructions, prompt-injection coverage and personal-data leaks.

## What we evaluated

| Feature (0.3)                                          | Without a script                                             | Kept?                                  |
| ------------------------------------------------------ | ------------------------------------------------------------ | -------------------------------------- |
| Routes, default reviewer, coverage check, stale routes | git pathspecs                                                | yes, exact                             |
| Changed-lines rules, `(?i)`                            | `git diff [-i] -G` (POSIX ERE)                               | yes, exact                             |
| Model rules (title, paths, added lines)                | `git log --format=%s --right-only`, pathspecs, `--shortstat` | yes; the subject match is a `grep -E`  |
| `[[expect]]` with untracked paths                      | throwaway git index                                          | yes, exact                             |
| Mirrors (regex substitution)                           | none                                                         | no: a route lists its tests as globs   |
| Fallbacks (first match)                                | possible but hard to follow                                  | no: a route                            |
| Import guards (Python import graph)                    | needs a parser                                               | no: a test in the consumer's own suite |
| reviewer-guard hook                                    | reviewers without Bash                                       | yes, stronger                          |
| haiku-reviewer-guard hook                              | inline hook line + reviewer self-check                       | yes                                    |
| Backlog and escape ledger helpers                      | `printenv`, Read, Edit, Grep                                 | yes; formats unchanged                 |
| Transcript miner (corrections, command sequences)      | one `grep` pipeline over `history.jsonl`                     | corrections only                       |

Checked before landing on the largest consumer, trading-system: its 0.3 config, converted to v2 as add-reviewer's "Migrating from 0.3" describes, gives the same reviewer set as the 0.3 router for all 432 tracked files and the 13 hypothetical paths in its 111 expect cases, and for twelve real commit ranges, including the case-insensitive changed-lines rule.

## Evals

We tried `claude plugin eval`. Cases can live outside the shipped plugin (repo-root `evals/<plugin>/` with `plugins: ["../../../plugins/<name>"]`, run as `claude plugin eval . --eval-dir evals/<plugin>`), `tool_used` sees an Agent call's `subagent_type` and `model`, the inline hook denied a real Haiku dispatch, and a subagent on Haiku names its model. But every case that grants Bash runs under Claude Code's OS sandbox, which cannot start in an unprivileged container (bubblewrap cannot mount `/proc`), and the owner cannot run evals elsewhere. So there is no eval suite. If one becomes possible, start from those findings.

## Consequences

- Pros: nothing to install but git; nothing executable to audit; reviewers are read-only by construction; every exact decision is made by git, and the commands are visible in the skill text.
- Cons: the model chains the commands, so a step can be skipped or misread; nothing measures that continuously without evals. Consumers had to migrate their configs (breaking release). Reviewers lose `git blame`, older file versions and throwaway hypothesis scripts. Repeated command sequences from earlier sessions are no longer reported. The Haiku guard is the one piece of shell a plugin ships.
- To revisit when: evals can run (a privileged container or a host with a sandbox), or Claude Code lets a plugin forbid a subagent model declaratively (then the inline hook goes).
