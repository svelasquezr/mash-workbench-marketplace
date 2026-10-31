# 0001. One catalog per tool, skills shared, Claude-format components kept

## Status
Accepted. Parts marked *unverified* have not been tried in the other tools.

## Context
The plugins were built for Claude Code and are meant to be usable from GitHub Copilot CLI and OpenCode later. Only Claude Code is supported today; support for the others is planned and has not been tried. What the documentation of each tool says (checked against their docs pages):
- **Copilot CLI** reads `skills/<name>/SKILL.md` in a plugin. Its documented marketplace catalog is `.github/plugin/marketplace.json`, and each entry's `source` points at a plugin folder, as in Claude Code. Copilot-only agents are `agents/<name>.agent.md`; its hooks and MCP config sit in Copilot-specific places. The page that describes plugin layout does not say whether Copilot reads `.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json`; a community repo reports that it does, which is *unverified*.
- **OpenCode** has no plugin-manifest or marketplace format. It reads `SKILL.md` files from `.opencode/skills/`, `.claude/skills/` and `.agents/skills/` (project) and the matching global folders; unknown frontmatter fields are ignored. Its plugins are JavaScript or TypeScript files, or npm packages listed in `opencode.json`. A skill inside `plugins/<name>/skills/` is not in one of those folders, so it is not found without an adapter or a copy.

## Decision
1. Contributor instructions live in `AGENTS.md`, which several tools read; `CLAUDE.md` is a one-line pointer to it.
2. `SKILL.md` files are the shared layer: `name` and `description` frontmatter only, scripts next to them.
3. The marketplace is listed twice with identical content: `.claude-plugin/marketplace.json` (Claude Code) and `.github/plugin/marketplace.json` (Copilot CLI). `tests/test_marketplace_files.sh` fails when they differ.
4. Skills are the only component used for behaviour that should travel, so there are no commands: `/forge` is a skill. Agents and hooks stay in Claude Code's formats. No `*.agent.md` or Copilot hook files are added until someone tests them in Copilot.
5. OpenCode is not targeted yet. When it is, the options are an adapter that loads Claude Code plugins, or a small npm package that points OpenCode at the skills.

## Consequences
- Pros: one source of truth for the skills; Claude Code users lose nothing; a second catalog is cheap and checked by a test.
- Cons: the agents and hooks, which hold much of the value of `review-routing`, do not reach the other tools yet; the duplicated catalog can drift if a tool starts to need different fields; Copilot support rests on one documented path and one unverified report.
- To revisit when: a plugin is tried in Copilot CLI or OpenCode, or either tool documents a Claude-compatible agent or hook format.
