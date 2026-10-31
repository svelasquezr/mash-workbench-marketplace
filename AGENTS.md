# mash-workbench-marketplace

This file is the contributor guide for every tool; `CLAUDE.md` only points here.

Plugin marketplace (brand MASH: Memories, Agents, Skills, Hooks) of general-purpose plugins for Claude Code. Support for GitHub Copilot CLI and other agents is planned, not yet available.

## Layout
- `.claude-plugin/marketplace.json` — Claude Code catalog (`source: ./plugins/<name>`); `.github/plugin/marketplace.json` — the same catalog, kept in the file Copilot CLI documents, for the planned Copilot CLI support (untested). They must stay identical, and each entry's description must equal its `plugin.json` description (`tests/test_marketplace_files.sh`).
- `plugins/<name>/` — `.claude-plugin/plugin.json`, `skills/<skill>/SKILL.md` (+ the skill's scripts next to it), `agents/*.md`, `hooks/hooks.json` (+ the hook's script next to it)
- `tests/test_*.sh` — bash tests for every script; `bash tests/run.sh`
- `docs/decisions/` — architecture decisions

## Working on this repo
- The tests' in-place edits use GNU sed (on macOS: `brew install gnu-sed`); the shipped scripts don't need it.
- Run `pre-commit install` once: it installs the commit-message hook (Conventional Commits) that CI also checks.
- `tests/test_reviewer_guard.sh` builds its fixture repositories under `$HOME` (the hook treats `/tmp` as throwaway), removes them on exit, and refuses to run when `$HOME` is under `/tmp`.
- `pre-commit` can run as `uvx pre-commit run --all-files`.
- Scripts and hooks need `python3` 3.11 or newer.

## Skill and agent conventions
- A skill's `description` says only when to use it (triggers, symptoms), never its steps: Claude may follow a summary instead of reading the skill.
- Skills run their scripts as `bash <this skill's base directory>/<script>.sh` (or `python3 …`): a bare path fails where the executable bit was lost.
- Keep a SKILL.md under ~500 words; point to another skill or a script's `--help` instead of repeating it.
- Agents declare `model:` and `effort:` (`tests/test_agent_frontmatter.sh` checks it) and the fewest `tools:` they need. Reviewers (agent files named `*reviewer*`, or whose file contains the `SAFE TO LAND` verdict line) are read-only and never run on `haiku`.
- Skills declare neither `model:` nor `effort:`, on purpose: they run inside the main conversation, and switching the model there re-reads the whole conversation without the prompt cache.
- Prefer a skill to a command: skills are the one component format other tools are expected to read too, and Claude Code shows a skill as `/<plugin>:<skill>`. Add a command only for something a skill cannot do.
- Other tools are planned, so a skill should be able to work in tools that read `SKILL.md`: use `name` and `description` as the only frontmatter, and do not make a skill depend on a Claude Code feature without saying what to do where it is missing.

## Rules
- Deterministic first: hook > script > skill > agent > MCP. Skills hold judgment and call scripts for mechanics.
- Every script gets a bash test written first. Before committing run `bash scripts/check.sh` (the tests, then `claude plugin validate --strict`) and `pre-commit run --all-files`; CI runs the same two.
- Bump the plugin's `version` in `plugin.json` on every change that consumers should receive.
- Test a plugin locally without publishing: `claude --plugin-dir plugins/<name>` from a consumer repo.
- No absolute paths in committed files. Explain reasoning with pros and cons in docs.
- Commits use Conventional Commits (enforced by the commitizen commit-msg hook).
