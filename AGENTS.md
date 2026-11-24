# mash-workbench-marketplace

This file is the contributor guide for every tool; `CLAUDE.md` only points here.

Plugin marketplace (brand MASH: Memories, Agents, Skills, Hooks) of general-purpose plugins for Claude Code. Support for GitHub Copilot CLI and other agents is planned, not yet available.

## Layout

- `.claude-plugin/marketplace.json` — Claude Code catalog (`source: ./plugins/<name>`); `.github/plugin/marketplace.json` — the same catalog, kept in the file Copilot CLI documents, for the planned Copilot CLI support (untested). They must stay identical, and each entry's description must equal its `plugin.json` description (`tests/test_marketplace_files.sh`).
- `plugins/<name>/` — `.claude-plugin/plugin.json`, `skills/<skill>/SKILL.md` (+ the skill's scripts next to it), `agents/*.md`, `hooks/hooks.json` (+ the hook's script next to it)
- `tests/test_*.sh` — bash tests for every script; `bash tests/run.sh`
- `docs/decisions/` — architecture decisions
- `docs/specs/<plugin>.md` — a plugin's design: its model, decisions, contracts and diagrams
- `evals/<plugin>/` — `claude plugin eval` cases, kept outside the plugin so they do not ship; `bash scripts/eval-<plugin>.sh` runs them on a copy (each case is a paid Claude session, so CI does not run them)

## Working on this repo

- The tests' in-place edits use GNU sed (on macOS: `brew install gnu-sed`); the shipped scripts don't need it.
- Run `pre-commit install` once: it installs the commit-message hook (Conventional Commits) that CI also checks.
- `pre-commit` can run as `uvx pre-commit run --all-files`.
- `tests/test_backlog_add.sh`, `test_consumer_safety.sh`, `test_git_dir_shape.sh`, `test_mash_settings.sh`, `test_plugin_current.sh` and `test_write_scope.sh` build their fixture repositories under `$HOME` (the scripts treat `/tmp` as throwaway), remove them on exit, and refuse to run when `$HOME` is under `/tmp`; `test_permission_rules.sh` also builds under `$HOME`.
- Only `past-friction.py` in mash-workbench is Python (3.11 or newer); it runs through the plugin's `scripts/python.sh`: on Windows, `python3` is often the Microsoft Store alias, which fails every call (`tests/test_find_python.sh`).
- `tests/test_no_network.sh` keeps its accepted lines in `tests/no_network_allowed.txt`, by file and line number: after you edit a file that has entries, run `NO_NETWORK_LIST=1 bash tests/test_no_network.sh` and update them.

## Skill and agent conventions

- A skill's `description` says only when to use it (triggers, symptoms), never its steps: Claude may follow a summary instead of reading the skill.
- Skills run their scripts as `bash <this skill's base directory>/<script>.sh` (or `bash <plugin>/scripts/python.sh …` for Python): a bare path fails where the executable bit was lost.
- Keep a SKILL.md under ~500 words; point to another skill or a script's `--help` instead of repeating it.
- Agents declare `model:` and `effort:` (`tests/test_agent_frontmatter.sh` checks it) and the fewest `tools:` they need. Reviewers (agent files named `*reviewer*`, or whose file contains the `SAFE TO LAND` verdict line) are read-only and never run on `haiku`.
- Skills declare neither `model:` nor `effort:`, on purpose: they run inside the main conversation, and switching the model there re-reads the whole conversation without the prompt cache.
- Prefer a skill to a command: skills are the one component format other tools are expected to read too, and Claude Code shows a skill as `/<plugin>:<skill>`. Add a command only for something a skill cannot do.
- Other tools are planned, so a skill should be able to work in tools that read `SKILL.md`: use `name` and `description` as the only frontmatter, and do not make a skill depend on a Claude Code feature without saying what to do where it is missing.

## Rules

- Instructions first: a plugin prefers skills and agents; a project adds hooks or scripts when it needs a guarantee (`docs/decisions/0007-instructions-first.md`). mash-workbench still has scripts until its own change; the script rules in this file apply to them.
- A change to a plugin's behavior updates the diagrams in its spec, `docs/specs/<plugin>.md`, in the same PR.
- Every script gets a bash test written first. Before committing run `bash scripts/check.sh` (the tests, then `claude plugin validate --strict`) and `pre-commit run --all-files`; CI runs the same two.
- Bump the plugin's `version` in `plugin.json` on every change that consumers should receive.
- Test a plugin locally without publishing: `claude --plugin-dir plugins/<name>` from a consumer repo.
- No absolute paths in committed files. Explain reasoning with pros and cons in docs.
- Scripts do not trust their input (`docs/decisions/0006-scripts-trust-no-input.md`): no argument names a file to read or write, a committed file cannot move a write outside the repository, a symbolic link is refused where a write would follow it, and text that goes to git cannot start with `-`. A script that can get an allow rule runs `scripts/plugin-current.sh` first. Each such rule has a test that plants the attack.
- Commits use Conventional Commits (enforced by the commitizen commit-msg hook).
