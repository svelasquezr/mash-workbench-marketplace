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
- Scripts and hooks need Python 3.11 or newer, and call it only through the plugin's `scripts/python.sh`: on Windows, `python3` is often the Microsoft Store alias, which fails every call. The file is the same in every plugin (`tests/test_find_python.sh`).
- Three more files are identical copies in both plugins, because an installed plugin cannot read another plugin's files: `scripts/mash-settings.sh` (`tests/test_find_python.sh`), `scripts/plugin-current.sh` (`tests/test_plugin_current.sh`) and `permission-rules.sh` (`tests/test_permission_rules.sh`). Change one, copy it to the other.
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

- Deterministic first: hook > script > skill > agent > MCP. Skills hold judgment and call scripts for mechanics.
- Every script gets a bash test written first. Before committing run `bash scripts/check.sh` (the tests, then `claude plugin validate --strict`) and `pre-commit run --all-files`; CI runs the same two.
- Bump the plugin's `version` in `plugin.json` on every change that consumers should receive.
- Test a plugin locally without publishing: `claude --plugin-dir plugins/<name>` from a consumer repo.
- No absolute paths in committed files. Explain reasoning with pros and cons in docs.
- Scripts do not trust their input (`docs/decisions/0006-scripts-trust-no-input.md`): no argument names a file to read or write, a committed file cannot move a write outside the repository, a symbolic link is refused where a write would follow it, and text that goes to git cannot start with `-`. A script that can get an allow rule runs `scripts/plugin-current.sh` first. Each such rule has a test that plants the attack.
- Commits use Conventional Commits (enforced by the commitizen commit-msg hook).
