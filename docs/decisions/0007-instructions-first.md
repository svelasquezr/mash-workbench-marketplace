# 0007: mash-review is made of instructions only

Status: accepted. It supersedes [0004](0004-escape-storage-and-settings.md) and [0005](0005-exact-path-allow-rules.md), and it supersedes [0006](0006-scripts-trust-no-input.md) for review-routing. 0006 continues to apply to the scripts of mash-workbench.

## Context

review-routing 0.6.0 used a Python router with nine modules, a Python hook of 828 lines and approximately 1,100 lines of bash. The router and the hook need Python 3.11 or a later version, because they read TOML with `tomllib`. These problems occurred:

1. **Python version.** Users reported this problem. A host had Python 3.9. The router stopped with exit code 3, and the review used only the default reviewer. The `reviewer-guard` hook ran `python.sh --missing-ok` and did no check. The expected result is a full review on each host.
2. **Operating systems.** On Windows, `python3` is often the Microsoft Store alias, and each call fails. The scripts that write have no test on Windows, so `permission-rules.sh` offers no rule there, and each write asks the user. The expected result is the same behavior on each operating system.
3. **Security.** The audit of 0006 found eight classes of security bugs in the scripts. The corrections added approximately 30 checks, and each new script must have the same checks. Each allow rule is a new risk. The expected result is a plugin that has no script that an allow rule can approve.
4. **Plan mode.** In plan mode, the skills ran the router, and they tried to write escape files, settings and the review log. The session ran tools when it must only make a plan. The expected result is a review plan, with no tool runs and no writes.
5. **Adoption.** No step made `.claude/reviewers.toml`, and no step proposed it. An escape needed a setup question, a settings file and allow rules before the first file. Users reported that the plugin did not record escapes. The expected result is that the first review and the first escape work with no setup.
6. **Too much control.** `review-changes` fixed the findings, made commits and started fix rounds. It did not use a builder skill for the fix. The expected result is that the review only reviews, and the user decides about fixes.

## Decision

1. **Instructions only.** The plugin `mash-review` 1.0.0 replaces review-routing. It contains skills and one agent. It contains no hook, no script, no config file and no allow rule.
2. **Standards are skills.** A review standard is a skill whose `description` tells when it applies. It is a "Review checklist" section in a builder skill, a companion skill that cites a builder skill, or a standalone review skill. The `review` skill selects the standards from the diff and the intent. Path routes and `reviewers.toml` are removed.
3. **One read-only reviewer.** The agent `mash-review:reviewer` has the tools `Read`, `Grep`, `Glob`, `Bash` and `Skill`. Its instructions permit only read-only git commands. It gets the diff and the history from git itself. The permission check of Claude Code refuses a write when no user is present in default mode.
4. **The review only reviews.** The `review` skill does not fix, commit, stash or push. A user who wants fixes asks the session. Each finding names its standard, and the standard names its builder skill.
5. **Escapes are checklist lines.** An escape becomes a line in the standard that covers it. When no standard covers it, the skill writes a file in `.mash-review/escapes/` in the main worktree. At three files on one topic, the skill offers a new standard. The skill writes only when a user is present. With no user present, the final report lists the escapes.
6. **Determinism is the work of the project.** A project forces a standard with a rule in its `CLAUDE.md` or `AGENTS.md`. A project adds hooks, tests or CI jobs when it needs a guarantee. The repository rule "Deterministic first" changes to "Instructions first".
7. **Rename.** The marketplace files map `review-routing` to `mash-review` with `renames`. The `migrate` skill moves a project from review-routing 0.x when the user asks for it.
8. **The specification holds the diagrams.** `docs/specs/mash-review.md` contains the design and its diagrams. A change to the behavior of a plugin updates the diagrams in its specification in the same pull request.

## Options that we did not select

- **Keep the scripts and correct the bugs.** Pros: the routing stays deterministic. Cons: the Python version, Windows and the security checks stay problems for each new script. The users did not use the plugin.
- **Write the router in bash.** Pros: no Python. Cons: bash is different on macOS (3.2), Linux and Git Bash. The security checks of 0006 stay necessary. The parser for TOML becomes our code.
- **Keep only the hook, in bash.** Pros: a guard against a reviewer that changes a file, also in `bypassPermissions` mode. Cons: the hook is a script, with the problems of item 2 and item 3 of the context. In the other modes, the permission check of Claude Code already asks before a write.
- **A reviewer with no Bash, and the diff in a file.** Pros: the reviewer cannot change a file. Cons: in `claude -p` with the default permission mode, Claude Code refused the redirect to the file and the `Read` of a file in `/tmp`. Thus a session with no user present cannot do a review without allow rules. We tested this on 2026-11-23 with Claude Code 2.1.330.
- **Paste the diff into each reviewer prompt.** Pros: the reviewer needs no Bash. Cons: the orchestrator writes the diff as output tokens one time for each reviewer. When the reviewer runs `git diff`, the diff is input only.
- **One reviewer agent for each area.** Pros: each agent has its own rules. Cons: the agents repeat the builder skills, and the two become different.
- **Keep the name review-routing.** Pros: no rename. Cons: the plugin no longer routes. Users ask for "mash review", and "code review" matches many plugins.
- **Escapes in `CLAUDE.md`.** Pros: no new folder. Cons: the file becomes longer with each escape, and each session loads it.

## Pros and cons

- Pros: the plugin works on each host that runs Claude Code, with no Python and no allow rules.
- Cons: in `bypassPermissions` mode, only the instruction stops a reviewer that runs a command that writes.
- Pros: there is no script, so there is no script attack surface and no security check to keep.
- Pros: one file holds the rules for the work and for its review, so the review and the builder agree.
- Pros: plan mode gives a plan, and nothing runs.
- Cons: the selection of standards is a judgment of the model. Two reviews of the same change can select different standards. A project that needs the same result each time adds a rule to `CLAUDE.md`, or its own hook or CI job.
- Cons: no record tells whether a review passed a commit. The reviewer answers during a review, and at other times the skill asks the user.
- Cons: a project that uses review-routing must run `migrate` once, and each user runs `/plugin install mash-review@mash-workbench-marketplace` once.
- Cons: `forge` in mash-workbench reads the old escape files and finds none after this change. A later change to mash-workbench corrects this.
- Cons: `AGENTS.md` says "Instructions first", but mash-workbench keeps its scripts and Python until that later change.
- Cons: the plugin's behavior has no bash tests. `claude plugin eval` suites and manual runs replace them, and they cost model calls.
