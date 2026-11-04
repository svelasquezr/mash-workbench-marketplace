# review-routing

A Claude Code plugin that sends each change to the reviewers it needs. A project lists its specialist reviewer agents and the paths each one covers in `.claude/reviewers.toml`; a general `change-reviewer` covers every path no specialist claims. Reviewers are read-only, have no shell, and end with a verdict line (`SAFE TO LAND` or not), which the `review-changes` summary checks.

The plugin ships no scripts: only skills, agents and one inline hook line. Git does every match (which files a route claims, which lines changed, how many lines were added), so routing gives the same answer every time; the skills tell Claude which git commands to run and how to combine their output.

## Install

```
/plugin marketplace add svelasquezr/mash-workbench-marketplace
/plugin install review-routing@mash-workbench-marketplace
```

To try it without installing: `claude --plugin-dir <path-to>/plugins/review-routing`.

## What it contains

| Part                                        | What it does                                                                                                                                                                                                                                                                                                                                       |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `review-changes` skill                      | before you open a pull request: picks the reviewers and their models for your committed changes, runs your checks first, dispatches the reviewers, triages findings and fixes what the change introduced; prints a summary in the terminal and writes nothing to a PR. Ask "which reviewers would this get?" for a preview that dispatches nothing |
| `add-reviewer` skill                        | adds a specialist reviewer when the same class of bug slips through review twice, checks `.claude/reviewers.toml`, migrates a 0.3 config, and records each missed bug in `docs/mash/review-escapes.md`                                                                                                                                             |
| `inspect` skill (`/review-routing:inspect`) | for a project that already has review habits: finds instructions in `CLAUDE.md`, `AGENTS.md`, memory or plans that would override the routing, and areas you already brief reviewers on by hand; proposes rewrites and applies only the ones you approve                                                                                           |
| `change-reviewer` agent                     | the default reviewer: correctness, tests for new branches, stale docs, unsupported claims, secrets, prompt injection. Tools: Read, Grep, Glob                                                                                                                                                                                                      |
| Haiku guard (hook)                          | one inline shell line in `hooks/hooks.json` that denies starting a reviewer on Haiku                                                                                                                                                                                                                                                               |

## Requirements

`git` and `grep` (plus `mkdir`, `rm` and `date`, which every Unix-like system has). Nothing needs `gh`, GitHub, Python or Node: the review works on a git range, whatever hosts the repository. Escape-ledger links from github.com are normalised; any other `https://` link is kept as given, unless it carries credentials or a token, which is refused. Built for Claude Code and developed against 2.1.318; older versions are untested. `inspect` reads the project's `CLAUDE.md` and `AGENTS.md` and, where they exist, `.claude/memory/`, `.claude/plans/` and the auto-memory folder under `~/.claude/projects/`.

## Opinionated defaults

- **Reviewers have no shell.** Their tools are Read, Grep and Glob. `review-changes` writes the change's diff to a file inside the git directory (`.git/review-routing/`, never committed) and gives the reviewer its path. A reviewer cannot change your checkout, write to GitHub, run a command or send anything anywhere, whatever a reviewed change tells it to do. What it gives up: reading older versions of files, `git blame` and running a throwaway script to test a hypothesis; it says so in its report when it needed one of those.
- **Reviewers never run on Haiku.** Three layers: `review-changes` always passes the model the routing gives (never Haiku), the hook denies a Haiku dispatch it recognises as a review, and every reviewer this plugin ships or templates answers `NOT SAFE` if it finds itself on Haiku. The add-reviewer check also refuses `model: haiku` in a reviewer file.
- Models in `.claude/reviewers.toml` are the aliases `sonnet`, `opus` and `fable`. Pin only models your plan can start: a reviewer pinned to a model you cannot use fails when it is dispatched.
- `general-purpose` is never a reviewer: it has every tool and no verdict format.

## Verdict format

Every reviewer this plugin runs, including the ones `add-reviewer` writes from its template, ends its review with exactly one line: `SAFE TO LAND` when it found no Critical and no Important problems, or `NOT SAFE: <why>` otherwise. Minor findings never block. `review-changes` calls the branch ready to open as a PR only when every reviewer's last verdict is `SAFE TO LAND`. The Haiku guard also reads the phrase in an agent's prompt as a sign that the agent is a reviewer. A reviewer you write by hand should end the same way, or `review-changes` cannot read its verdict.

## What the hook does to your session

The hook applies in every project once the plugin is enabled. It runs on every Agent call (a few milliseconds), writes nothing and reads only the call's input. It denies the call when the model is Haiku and the call looks like a review: the agent's name contains `reviewer`, or the prompt contains `SAFE TO LAND` or `Critical / Important / Minor`. Anything else passes, and so does everything when `grep` is missing. The only way to switch it off is to disable the plugin.

You can also add `"Agent(model:haiku)"` to `permissions.deny` in your own settings (a plugin cannot ship permission rules). Tested with Claude Code 2.1.318: an Agent call that passes `model: haiku` is then denied for any agent (see Claude Code's [permissions docs](https://code.claude.com/docs/en/permissions)); the rule does not see a model set only in an agent file.

## Permission prompts

`review-changes` runs one plain git command per Bash call, so each one can be approved on its own. `git rev-parse` only prints (no option of it writes a file, as of git 2.55), so `"Bash(git rev-parse:*)"` is the one rule worth considering. Think twice before allowing any `git diff` or `git log` prefix, however narrow (`Bash(git diff --name-only:*)` included): both commands accept `--output=<file>`, so such a rule also lets Claude write any file you can write without asking. Commands that write on purpose (`mkdir -p`, `rm -f`, the redirects that write the diff file, `git update-index` on the throwaway index) should keep asking.

## What it writes

Only when you or Claude run the matching skill: the diff file for reviewers and, for the check, a throwaway index and its input list (`expect.index`, `expect.list`), all under `.git/review-routing/` and never committed (`review-changes`, `add-reviewer`), `docs/mash/review-escapes.md` (`add-reviewer` and `review-changes`, one line per missed bug; only after you chose where it lives), `.claude/reviewers.toml` and `.claude/agents/<name>.md` (`add-reviewer`, new reviewers), fix commits for what a review finds (`review-changes`; it never pushes, opens a PR or merges), a line in `CLAUDE.md` naming your check commands when you accept it (`review-changes`), and edits to `CLAUDE.md` or memory files that you approve (`inspect`).

## Upgrading from 0.3

0.4 is a breaking release: the plugin no longer ships its Python router and hooks.

- **`.claude/reviewers.toml` needs `version = 2`.** Patterns are now git paths (`src/payments` instead of `'^src/payments/'`). `[[mirrors]]` and `[[fallbacks]]` become routes, and `[[import_guards]]` becomes a test in your own suite. Ask Claude to migrate it: the add-reviewer skill's "Migrating from 0.3" has the table, and its check proves every `[[expect]]` still holds. Until then, `review-changes` stops with a pointer to the migration.
- **Reviewer agents lose Bash.** Set `tools: Read, Grep, Glob` in each `.claude/agents/*-reviewer.md`, and replace the sentence about `git show`/`git archive` with the template's diff-file paragraph. The check flags any reviewer that still has a shell.
- **Python is no longer needed**, and the `reviewer-guard` hook is gone: a reviewer without a shell has nothing to guard.

## Where the escape ledger lives

The first time a bug needs recording, the skill asks whether to create `docs/mash/review-escapes.md`, use another file, or keep none. To answer once, set `REVIEW_ROUTING_ESCAPES` (a path relative to the repository, or `off`) in the `env` block of `.claude/settings.local.json` (only you) or `.claude/settings.json` (everyone). A ledger already at `docs/review-escapes.md` keeps working where it is; move it with `git mv` when you like. It offers to add a new ledger to `.gitignore`; an ignored ledger counts only your own escapes, so the default is to commit it and let the whole team's misses add up.

## Why reviewers are routed

One general reviewer misses what a specialist would catch, and a specialist for every path costs more than it saves. Routing by path keeps the cheap general reviewer as the default and adds a specialist only where a miss is expensive or has already happened.

## Uninstall and support

`/plugin uninstall review-routing@mash-workbench-marketplace`. Files the plugin wrote into your repositories stay; delete them if you do not want them. Report a problem or ask a question at https://github.com/svelasquezr/mash-workbench-marketplace/issues.

## License

MIT, see [LICENSE](LICENSE).
