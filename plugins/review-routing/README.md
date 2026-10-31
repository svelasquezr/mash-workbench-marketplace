# review-routing

A Claude Code plugin that sends each change to the reviewers it needs. A project lists its specialist reviewer agents and the paths each one covers in `.claude/reviewers.toml`; a general `change-reviewer` covers every path no specialist claims. Reviewers are read-only and end with a verdict line (`SAFE TO LAND` or not), which the landing step checks.

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install review-routing@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/review-routing`.

## What it contains

| Part | What it does |
|---|---|
| `review-changes` skill | before you open a pull request: picks the reviewers and their models for your committed changes, runs your checks first, dispatches the reviewers, triages findings and fixes what the change introduced; prints a summary in the terminal and writes nothing to a PR |
| `add-reviewer` skill | adds a specialist reviewer when the same class of bug slips through review twice, and records each missed bug in `docs/review-escapes.md` |
| `inspect` skill (`/review-routing:inspect`) | for a project that already has review habits: finds instructions in `CLAUDE.md`, `AGENTS.md`, memory or plans that would override the routing, and areas you already brief reviewers on by hand; proposes rewrites and applies only the ones you approve |
| `change-reviewer` agent | the default, read-only reviewer: correctness, tests for new branches, stale docs, unsupported claims, secrets |
| `reviewer-guard` hook | refuses the plugin's reviewers (its own agents and the ones your `.claude/reviewers.toml` names) their non-read git commands (in a real repository, not a scratch one) and their GitHub-writing `gh` commands (a guard against accidents, not a security boundary; the gaps are listed in the hook's docstring) |
| `haiku-reviewer-guard` hook | refuses to start a reviewer on Haiku (a heuristic: it recognises a reviewer by its name or by verdict words in the prompt) |

## Requirements

`git`, `bash` and `python3` 3.11 or newer. Nothing needs `gh` or GitHub: the review works on a git range, whatever hosts the repository. Escape-ledger links from github.com are normalised; any other http(s) link is kept as given. Built for Claude Code and developed against 2.1.289; older versions are untested. `inspect` reads the project's `CLAUDE.md` and `AGENTS.md` and, where they exist, `.claude/memory/`, `.claude/plans/` and the auto-memory folder under `~/.claude/projects/`.

## Opinionated defaults

- Reviewers never run on Haiku: the hook refuses it and the routing config rejects it. There is no opt-out other than disabling the plugin (see the hooks section below).
- Models in `.claude/reviewers.toml` are the aliases `sonnet`, `opus` and `fable`, the ones Claude Code's agent tool accepted when this plugin was written. If your Claude Code accepts other aliases, the config check rejects them until the list in `route_types.py` is updated. Pin only models your plan can start: a reviewer pinned to a model you cannot use fails when it is dispatched.

## Verdict format

Every reviewer this plugin runs, including the ones `add-reviewer` writes from its template, ends its review with exactly one line: `SAFE TO LAND` when it found no Critical and no Important problems, or `NOT SAFE: <why>` otherwise. Minor findings never block. `review-changes` calls the branch ready to open as a PR only when every reviewer's last verdict is `SAFE TO LAND`. The `haiku-reviewer-guard` hook also reads the phrase in an agent's prompt as a sign that the agent is a reviewer. A reviewer you write by hand should end the same way, or `review-changes` cannot read its verdict. Reviewer files copied from an older version of the template may still say "ready for `gh issue create`" under Pre-existing; they keep working, and the new wording is "ready to file as an issue".

## What the hooks do to your session

Both hooks apply in every project once the plugin is enabled, not only in projects that use review routing. They run on every Bash call and every Agent call (around 15 ms each; for a reviewer's git command that is not a plain read, `reviewer-guard` also runs `git rev-parse` once per directory and git dir the command touches) and write nothing.

- `reviewer-guard` acts only for this plugin's reviewers: its own `review-routing:` agents, and the agents your `.claude/reviewers.toml` names. Any other agent, including your own review-posting agent, is left alone.
- It needs the `agent_type` field in the hook input, which names the subagent (`review-routing:change-reviewer`; a bare `change-reviewer` is recognised too). A Claude Code version that does not send it makes the guard do nothing.
- Claude Code's built-in agents (`general-purpose`, `Explore`, `Plan`, ...) are never guarded, even when your config names one as a reviewer: the same agent type also builds and commits in that session.
- `haiku-reviewer-guard` refuses an Agent call on Haiku when the call looks like a review.
- Both need `python3` on your PATH and do nothing without it.
- The only way to switch them off is to disable the plugin.

## What it writes

Only when you or Claude run the matching skill: `docs/review-escapes.md` (`add-reviewer` and `review-changes`, one line per missed bug), `.claude/reviewers.toml` and `.claude/agents/<name>.md` (`add-reviewer`, new reviewers), fix commits for what a review finds (`review-changes`; it never pushes, opens a PR or merges), and edits to `CLAUDE.md` or memory files that you approve (`inspect`).

## Why reviewers are routed

One general reviewer misses what a specialist would catch, and a specialist for every path costs more than it saves. Routing by path keeps the cheap general reviewer as the default and adds a specialist only where a miss is expensive or has already happened.

## Uninstall and support

`/plugin uninstall review-routing@mash-workbench-marketplace`. Files the plugin wrote into your repositories stay; delete them if you do not want them. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
