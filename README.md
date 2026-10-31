# mash-workbench-marketplace

A plugin marketplace for Claude Code (support for GitHub Copilot CLI and other coding agents is planned, not yet available), under the brand **MASH**: **M**emories, **A**gents, **S**kills, **H**ooks. These are the places an instruction to a coding agent can live. Scripts and MCP servers are the other two rungs of the same ladder, and the plugins here treat them as first-class: the aim is to put each rule in the most deterministic place that fits (hook, then script, then skill, then agent, then MCP server) instead of leaving it as prose the agent may forget.

## Plugins

| Plugin | What it does |
|---|---|
| [`mash-workbench`](plugins/mash-workbench) | notes repeated work as tooling candidates during a session (`scout`), then turns the approved ones into hooks, scripts, skills, agents or MCP servers (`/forge`) |
| [`review-routing`](plugins/review-routing) | sends each change to the reviewers it needs, from a per-project list of specialists, and lands it only on a clean verdict |

## Requirements

Claude Code, with `git`, `bash` and `python3` 3.11 or newer on your PATH (the scripts and hooks use the standard library only). `review-routing` also needs GitHub and the `gh` CLI; see its README.

## Install

In Claude Code:

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
/plugin install review-routing@mash-workbench-marketplace
```

## Other tools

**Only Claude Code is supported today.** The plugins are built and tested there, and nothing has been tried in any other tool. We plan to add support for GitHub Copilot CLI and other coding assistants, but that work has not been done.

What exists so far is groundwork, not support: the skills are plain `SKILL.md` files, a format other tools also read, and the marketplace is mirrored in `.github/plugin/marketplace.json`, the catalog file Copilot CLI documents. Agents, commands and hooks follow Claude Code's formats, so all of `review-routing` (its value is in its agents and hooks) is Claude Code only. Even the portable skills `scout` and `forge` depend on Claude Code for installation, automatic triggering and reading earlier-session transcripts. The reasoning and the open questions are in [docs/decisions/0001-cross-tool-layout.md](docs/decisions/0001-cross-tool-layout.md).

## Uninstall and support

`/plugin uninstall <plugin>@mash-workbench-marketplace`, and `/plugin marketplace remove mash-workbench-marketplace` to drop the marketplace. Report a problem at https://github.com/svelasquezr/mash-workbench-marketplace/issues. What each plugin writes, and what the `review-routing` hooks do to every session, is in the plugin READMEs.

## Contributing

See [AGENTS.md](AGENTS.md) for the layout, conventions and checks.

## License

MIT, see [LICENSE](LICENSE).
