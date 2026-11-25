# mash-workbench-marketplace

A plugin marketplace for Claude Code (support for GitHub Copilot CLI and other coding agents is planned, not yet available), under the brand **MASH**: **M**emories, **A**gents, **S**kills, **H**ooks. These are the places an instruction to a coding agent can live. Scripts and MCP servers are the other two rungs of the same ladder. The plugins here prefer instructions (skills and agents), which work on every operating system with no runtime to install, and leave hooks and scripts to projects that need a guarantee ([docs/decisions/0007-instructions-first.md](docs/decisions/0007-instructions-first.md)).

## Plugins

| Plugin                                     | What it does                                                                                                                                                                                    |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`mash-workbench`](plugins/mash-workbench) | notes repeated work as tooling candidates during a session (`scout`), then turns the approved ones into hooks, scripts, skills, agents or MCP servers (`/forge`); instructions only             |
| [`mash-review`](plugins/mash-review)       | reviews a change against your project's review standards (skills), records the bugs a review passed, and turns them into new standards; instructions only; `review-routing` renamed and rebuilt |

## Requirements

Claude Code and `git`. Both plugins are made of instructions only: no Python, no scripts and no allow rules.

## Install

In Claude Code:

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
/plugin install mash-review@mash-workbench-marketplace
```

`review-routing` was renamed **and rebuilt** as `mash-review`: the scripts, hook and config file are gone, and the plugin is made of instructions only. The marketplace renames it in your settings. Run the `mash-review` install line once, then `/mash-review:migrate` in each project that used it, and remove the old allow rules that the 1.0.0 entry of [plugins/mash-review/CHANGELOG.md](plugins/mash-review/CHANGELOG.md) lists. Also run `/mash-workbench:migrate` where mash-workbench 0.x was used: it removes the `backlog-add.sh` rule that entry said to keep.

## Other tools

**Only Claude Code is supported today.** The plugins are built and tested there, and nothing has been tried in any other tool. We plan to add support for GitHub Copilot CLI and other coding assistants, but that work has not been done.

What exists so far is groundwork, not support: the skills are plain `SKILL.md` files, a format other tools also read, and the marketplace is mirrored in `.github/plugin/marketplace.json`, the catalog file Copilot CLI documents. Agents, commands and hooks follow Claude Code's formats, so the `mash-review` reviewer agent is Claude Code only; its skills say what to do where there are no subagents. Even the portable skills `scout` and `forge` depend on Claude Code for installation and automatic triggering. The reasoning and the open questions are in [docs/decisions/0001-cross-tool-layout.md](docs/decisions/0001-cross-tool-layout.md).

## Uninstall and support

`/plugin uninstall <plugin>@mash-workbench-marketplace`, and `/plugin marketplace remove mash-workbench-marketplace` to drop the marketplace. Report a problem at https://github.com/svelasquezr/mash-workbench-marketplace/issues. What each plugin writes is in the plugin READMEs.

## Contributing

See [AGENTS.md](AGENTS.md) for the layout, conventions and checks.

## License

MIT, see [LICENSE](LICENSE).
