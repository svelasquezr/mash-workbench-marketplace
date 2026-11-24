# mash-workbench-marketplace

A plugin marketplace for Claude Code (support for GitHub Copilot CLI and other coding agents is planned, not yet available), under the brand **MASH**: **M**emories, **A**gents, **S**kills, **H**ooks. These are the places an instruction to a coding agent can live. Scripts and MCP servers are the other two rungs of the same ladder. The plugins here prefer instructions (skills and agents), which work on every operating system with no runtime to install, and leave hooks and scripts to projects that need a guarantee ([docs/decisions/0007-instructions-first.md](docs/decisions/0007-instructions-first.md)).

## Plugins

| Plugin                                     | What it does                                                                                                                                                                     |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`mash-workbench`](plugins/mash-workbench) | notes repeated work as tooling candidates during a session (`scout`), then turns the approved ones into hooks, scripts, skills, agents or MCP servers (`/forge`)                 |
| [`mash-review`](plugins/mash-review)       | reviews a change against your project's review standards (skills), records the bugs a review passed, and turns them into new standards; instructions only (was `review-routing`) |

## Requirements

Claude Code and `git`. `mash-workbench` also needs `bash`, and Python 3.11 or newer for `past-friction.py`, found as `python3`, `python` or the Windows launcher `py -3` (the Microsoft Store alias does not count; `MASH_PYTHON` chooses one; it uses the standard library only). `mash-review` needs nothing more.

## Install

In Claude Code:

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install mash-workbench@mash-workbench-marketplace
/plugin install mash-review@mash-workbench-marketplace
```

`review-routing` is now `mash-review`: the marketplace renames it in your settings. Run the `mash-review` install line once, then `/mash-review:migrate` in each project that used it, and remove the old allow rules that the 1.0.0 entry of [plugins/mash-review/CHANGELOG.md](plugins/mash-review/CHANGELOG.md) lists.

## Other tools

**Only Claude Code is supported today.** The plugins are built and tested there, and nothing has been tried in any other tool. We plan to add support for GitHub Copilot CLI and other coding assistants, but that work has not been done.

What exists so far is groundwork, not support: the skills are plain `SKILL.md` files, a format other tools also read, and the marketplace is mirrored in `.github/plugin/marketplace.json`, the catalog file Copilot CLI documents. Agents, commands and hooks follow Claude Code's formats, so the `mash-review` reviewer agent is Claude Code only; its skills say what to do where there are no subagents. Even the portable skills `scout` and `forge` depend on Claude Code for installation, automatic triggering and reading earlier-session transcripts. The reasoning and the open questions are in [docs/decisions/0001-cross-tool-layout.md](docs/decisions/0001-cross-tool-layout.md).

## Uninstall and support

`/plugin uninstall <plugin>@mash-workbench-marketplace`, and `/plugin marketplace remove mash-workbench-marketplace` to drop the marketplace. Report a problem at https://github.com/svelasquezr/mash-workbench-marketplace/issues. What each plugin writes is in the plugin READMEs.

## Contributing

See [AGENTS.md](AGENTS.md) for the layout, conventions and checks.

## License

MIT, see [LICENSE](LICENSE).
