# mash-workbench-marketplace

This file is the contributor guide for every tool; `CLAUDE.md` only points here.

Plugin marketplace (brand MASH: Memories, Agents, Skills, Hooks) of general-purpose plugins for Claude Code. Support for GitHub Copilot CLI and other agents is planned, not yet available.

## Layout

- `.claude-plugin/marketplace.json` — Claude Code catalog (`source: ./plugins/<name>`); `.github/plugin/marketplace.json` — the same catalog, kept in the file Copilot CLI documents, for the planned Copilot CLI support (untested). They must stay identical, and each entry's description must equal its `plugin.json` description (`tests/test_marketplace_files.sh`).
- `plugins/<name>/` — `.claude-plugin/plugin.json`, `skills/<skill>/SKILL.md` (+ its reference and template files next to it), `agents/*.md`; no scripts, hooks or Python (ADRs 0007, 0008)
- `tests/test_*.sh` — bash tests for the repository scripts and the catalog, skill and agent conventions; `bash tests/run.sh`
- `docs/decisions/` — architecture decisions
- `docs/specs/<plugin>.md` — a plugin's design: its model, decisions, contracts and diagrams
- `evals/<plugin>/` — `claude plugin eval` cases, kept outside the plugin so they do not ship; `bash scripts/eval.sh <plugin>` runs them on a copy (each case is a paid Claude session, so CI does not run them)

## Working on this repo

- The tests' in-place edits use GNU sed (on macOS: `brew install gnu-sed`); the shipped scripts don't need it.
- Run `pre-commit install` once: it installs the commit-message hook (Conventional Commits) that CI also checks.
- `pre-commit` can run as `uvx pre-commit run --all-files`.
- `tests/test_no_network.sh` keeps its accepted lines in `tests/no_network_allowed.txt`, by file and line number: after you edit a file that has entries, run `NO_NETWORK_LIST=1 bash tests/test_no_network.sh` and update them.

## Skill and agent conventions

- A skill's `description` says only when to use it (triggers, symptoms), never its steps: Claude may follow a summary instead of reading the skill.
- A plugin skill names no script: the model does the work with its own tools, and in the default permission mode Claude Code's permission check guards the writes (`tests/test_skill_script_paths.sh`; ADR 0008 names the modes where it does not). A skill that needs a guarantee tells the project to add its own hook, test or CI job.
- Keep a SKILL.md under ~500 words; point to another skill or a `reference.md` next to it instead of repeating it.
- Agents declare `model:` and `effort:` (`tests/test_agent_frontmatter.sh` checks it) and the fewest `tools:` they need. Reviewers (agent files named `*reviewer*`, or whose file contains the `SAFE TO LAND` verdict line) are read-only and never run on `haiku`.
- Skills declare neither `model:` nor `effort:`, on purpose: they run inside the main conversation, and switching the model there re-reads the whole conversation without the prompt cache.
- Prefer a skill to a command: skills are the one component format other tools are expected to read too, and Claude Code shows a skill as `/<plugin>:<skill>`. Add a command only for something a skill cannot do.
- Other tools are planned, so a skill should be able to work in tools that read `SKILL.md`: use `name` and `description` as the only frontmatter, and do not make a skill depend on a Claude Code feature without saying what to do where it is missing.

## Rules

- Instructions first: a plugin prefers skills and agents; a project adds hooks or scripts when it needs a guarantee (`docs/decisions/0007-instructions-first.md`).
- A change to a plugin's behavior updates the diagrams in its spec, `docs/specs/<plugin>.md`, in the same PR.
- Every script in `scripts/` gets a bash test written first. Before committing run `bash scripts/check.sh` (the tests, then `claude plugin validate --strict`) and `pre-commit run --all-files`; CI runs the same two.
- Bump the plugin's `version` in `plugin.json` on every change that consumers should receive.
- Test a plugin locally without publishing: `claude --plugin-dir plugins/<name>` from a consumer repo.
- No absolute paths in committed files. Explain reasoning with pros and cons in docs.
- Commits use Conventional Commits (enforced by the commitizen commit-msg hook).
