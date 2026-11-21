# review-routing

A Claude Code plugin that sends each change to the reviewers it needs. A project lists its specialist reviewer agents and the paths each one covers in `.claude/reviewers.toml`; a general `change-reviewer` covers every path no specialist claims. Reviewers are read-only and end with a verdict line (`SAFE TO LAND` or not), which the `review-changes` summary checks.

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install review-routing@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/review-routing`.

## What it contains

| Part                                        | What it does                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `review-changes` skill                      | before you open a pull request: picks the reviewers and their models for your committed changes, runs your checks first, dispatches the reviewers, triages findings and fixes what the change introduced; prints a summary in the terminal and writes nothing to a PR                                           |
| `add-reviewer` skill                        | adds a specialist reviewer when the bugs a review passed in one area reach the escape threshold (default 3), and records each one as a file in `.claude/mash-workbench/escapes/`                                                                                                                                |
| `inspect` skill (`/review-routing:inspect`) | for a project that already has review habits: finds instructions in `CLAUDE.md`, `AGENTS.md`, memory or plans that would override the routing, and areas you already brief reviewers on by hand; proposes rewrites and applies only the ones you approve                                                        |
| `change-reviewer` agent                     | the default, read-only reviewer: correctness, tests for new branches, stale docs, unsupported claims, secrets                                                                                                                                                                                                   |
| `reviewer-guard` hook                       | refuses the plugin's reviewers (its own agents and the ones your `.claude/reviewers.toml` names) their non-read git commands (in a real repository, not a scratch one) and their GitHub-writing `gh` commands (a guard against accidents, not a security boundary; the gaps are listed in the hook's docstring) |

## Requirements

`git`, `bash` and Python 3.11 or newer, found as `python3`, `python` or the Windows launcher `py -3` (the Microsoft Store alias does not count; set `MASH_PYTHON` to choose one: a command such as `py -3.12`, or a full path to the interpreter, which may hold spaces but then takes no arguments). With none, the review runs only the general reviewer and says routing was skipped. Nothing needs `gh` or GitHub: the review works on a git range, whatever hosts the repository. Recording an escape needs only `bash` (no `python3`), and the skills say how to write the file by hand if the script cannot run. Source links from github.com are normalised; any other http(s) link is kept as given. Built for Claude Code and developed against 2.1.289; older versions are untested. `inspect` reads the project's `CLAUDE.md` and `AGENTS.md` and, where they exist, `.claude/memory/`, `.claude/plans/` and the auto-memory folder under `~/.claude/projects/`.

## Opinionated defaults

- The routing config rejects Haiku, the router never prints it, and `review-changes` tells the session to use the models the router prints. Nothing checks a direct dispatch or a fix-round dispatch any more.
- Models in `.claude/reviewers.toml` are the aliases `sonnet`, `opus` and `fable`, the ones Claude Code's agent tool accepted when this plugin was written. If your Claude Code accepts other aliases, the config check rejects them until the list in `route_types.py` is updated. Pin only models your plan can start: a reviewer pinned to a model you cannot use fails when it is dispatched.

## Verdict format

Every reviewer this plugin runs, including the ones `add-reviewer` writes from its template, ends its review with exactly one line: `SAFE TO LAND` when it found no Critical and no Important problems, or `NOT SAFE: <why>` otherwise. Minor findings never block. `review-changes` calls the branch ready to open as a PR only when every reviewer's last verdict is `SAFE TO LAND`. A reviewer you write by hand should end the same way, or `review-changes` cannot read its verdict. Reviewer files copied from an older version of the template may still say "ready for `gh issue create`" under Pre-existing; they keep working, and the new wording is "ready to file as an issue".

## What the hook does to your session

The hook applies in every project once the plugin is enabled, not only in projects that use review routing. It runs on every Bash call (around 15 ms each; for a reviewer's git command that is not a plain read, `reviewer-guard` also runs `git rev-parse` once per directory and git dir the command touches) and writes nothing.

- `reviewer-guard` acts only for this plugin's reviewers: its own `review-routing:` agents, and the agents your `.claude/reviewers.toml` names. Any other agent, including your own review-posting agent, is left alone.
- It needs the `agent_type` field in the hook input, which names the subagent (`review-routing:change-reviewer`; a bare `change-reviewer` is recognised too). A Claude Code version that does not send it makes the guard do nothing.
- Claude Code's built-in agents (`general-purpose`, `Explore`, `Plan`, ...) are never guarded, even when your config names one as a reviewer: the same agent type also builds and commits in that session.
- It finds Python the same way as the skills (`scripts/python.sh`) and does nothing without it. The interpreter probe adds one Python start to each call.
- The only way to switch it off is to disable the plugin.

## What it writes

Only when you or Claude run the matching skill: one file per missed bug in the escapes folder, `.claude/mash-workbench/escapes/` by default, and the settings files next to it in `.claude/mash-workbench/` (`add-reviewer` and `review-changes`; only after you chose where escapes live), `.claude/reviewers.toml` and `.claude/agents/<name>.md` (`add-reviewer`, new reviewers), fix commits for what a review finds (`review-changes`; it never pushes, opens a PR or merges), a line in `CLAUDE.md` naming your check commands when you accept it (`review-changes`), and edits to `CLAUDE.md` or memory files that you approve (`inspect`).

## Upgrading from 0.1.0

`review-pr` is now `review-changes` and no longer opens, comments on or merges pull requests, so nothing needs `gh`. Text in your `CLAUDE.md` or memory that names `review-pr` (add-reviewer used to suggest such a rule) should name `review-changes`; `/review-routing:inspect` finds and proposes those rewrites. The routing script's `--pr` option is gone: pass a range.

## Where escapes live

An escape is a bug in code that a review passed. Each one is a file, `<date>-<slug>.md`, that describes the bug, so `add-reviewer` builds a checklist without asking a git host. The files live in one folder that every worktree of the repository finds: the settings are read from the main worktree (the folder where you cloned the repository), in `.claude/mash-workbench/settings` (for the team; commit it) and `settings.local` (only you; git ignores it through `info/exclude`). The first time a bug needs recording, the skill asks where to keep escapes: `.claude/mash-workbench/escapes` committed (the default, so the whole team's misses add up), the same folder excluded, another folder, or none. `REVIEW_ROUTING_ESCAPES` in the environment still wins over both files. The folder's `README.md` names the repository that owns it, and a folder another repository owns is refused, as are a linked worktree and a temporary folder. New escape files appear as uncommitted changes in the main worktree; no skill commits them.

Setup also offers to add allow rules for the recording scripts to `.claude/settings.local.json` in the main worktree, so background sessions in new worktrees record without a prompt; it adds them only on your yes. With the sandbox on, a session in a linked worktree also needs `sandbox.enabled`, `sandbox.autoAllowBashIfSandboxed` and `sandbox.filesystem.allowWrite` naming the escapes folder (in a container also `enableWeakerNestedSandbox`). A repository file cannot set `autoAllowBashIfSandboxed`, so the plugin does not try: set them in your own settings.

A ledger in the old one-line format (`docs/mash/review-escapes.md` or `docs/review-escapes.md`) is still counted, but nothing new is recorded until you migrate it: the skill explains and asks, then runs `escape-migrate.sh`, which writes one file per line and leaves the old file for you to remove.

## Why reviewers are routed

One general reviewer misses what a specialist would catch, and a specialist for every path costs more than it saves. Routing by path keeps the cheap general reviewer as the default and adds a specialist only where a miss is expensive or has already happened.

## Uninstall and support

`/plugin uninstall review-routing@mash-workbench-marketplace`. Files the plugin wrote into your repositories stay; delete them if you do not want them. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
