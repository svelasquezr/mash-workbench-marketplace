# mash-review

Status: target design for mash-review 1.0.0, which replaces review-routing 0.x. The reasons and the options we did not select are in [ADR 0007](../decisions/0007-instructions-first.md).

A change to the plugin's behavior updates the diagrams in this file in the same pull request.

## At a glance

- **What it is:** five skills (`review`, `record-escape`, `add-standard`, `inspect`, `migrate`) and one read-only `reviewer` agent. No Python, no hook, no script.
- **How a review works:** the `review` skill picks the project's review standards (skills) that fit the change, runs the project's checks once, and starts one reviewer for each group of standards. The reviewer runs read-only git itself and ends with `SAFE TO LAND` or `NOT SAFE`. The skill prints a summary and changes no code.
- **Escapes:** a bug that a review passed becomes a checklist line in the standard that covers it, or a file in `.mash-review/escapes/` until three on one topic make a new standard.
- **No user present** (`claude -p`, background runs): nothing is written; the report lists what needs the user.
- **Determinism** is the project's choice: rules in `CLAUDE.md` or `AGENTS.md`, or its own hooks, tests and CI.
- **Read next:** the diagrams below show each flow; the decisions D1 to D25 give the details and are numbered in reading order.

## Purpose

mash-review reviews a change against the project's **review standards**, and it records the bugs that a review passed (**escapes**) so that the standards get better. It is made of instructions only: skills and one read-only agent. It ships no hook, no script and no config file, so it needs no Python, works the same on every operating system, and asks for no allow rules.

It does not fix, commit, stash or push. A user who wants fixes asks the session for them; the session fixes with the builder skill that each finding's standard names.

It does not promise a deterministic result. A project that needs a guarantee adds it itself (see [Project determinism](#project-determinism)).

## Terms

- **Base:** `git merge-base <default branch> HEAD`, or a base the user names.
- **Change:** the diff under review. By default `git diff <base>...HEAD`; in working-tree mode, `<base>` against the working tree. Commit lists and counts always use `<base>..HEAD` (two dots): with `git log`, three dots also lists the commits that the default branch got after the branch point.
- **Intent:** what the change is for, from the commit messages, the pull request text or the user.
- **Review standard:** a skill whose `description` says when it applies, with the checks a reviewer applies. It is one of three kinds: a "Review checklist" section in a builder skill, a **companion** review skill that cites a builder skill, or a **standalone** review skill for a domain (payments, auth) or a project rule.
- **Builder skill:** a skill that says how to write a kind of code (an Angular component, a migration). It can come from the project or from another plugin.
- **Orchestrator:** the `review` skill, which runs in the main session.
- **Reviewer:** the `mash-review:reviewer` agent, started once for each group of standards.
- **General checklist:** the reviewer agent's own checklist (correctness, tests, stale docs, secrets). It applies in every review, also when no standard is selected; its findings name the standard `general`.
- **Escape:** a behavior bug (a wrong result, data lost, a guard bypassed) in code that a review passed.
- **User present:** a person can answer a question in this conversation, in any permission mode, auto mode included. A session that started from one prompt with no conversation (`claude -p`, `claude --bg`, a scheduled run), or whose prompt says nobody can answer, has no user present: it asks nothing, takes each step's default, and says so in its report. A later answer to that report, in any session, counts as the user's answer.
- **Main worktree:** the first `worktree` line of `git worktree list --porcelain`, where the repository was cloned.

## Core model

- A review compares a change against standards. Its inputs are the diff, the intent, the check results and the standards.
- The orchestrator selects standards by meaning: it matches the diff and the intent to each standard's `description`, then adds the standards that the project's `CLAUDE.md` or `AGENTS.md` requires. It writes down which standards apply and why. A path is a hint, never the rule: one folder can hold components, services and domain code.
- One generic reviewer agent runs once for each group of standards, on a model the orchestrator gives for each start. Every reviewer also applies the general checklist, so a change that matches no standard still gets one reviewer.
- A finding names the standard it broke. A fix uses the builder skill that standard names, so the session that fixes knows which builder to use.
- An escape becomes a checklist line in the standard it belongs to. With no matching standard, it waits as a file until three escapes on one topic justify a new standard.

### Why standards are skills

| Option                                            | Pros                                                                                                                                                 | Cons                                                                                        |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Skills selected by `description` (selected)       | One file for writing and reviewing; Claude Code and Copilot CLI both read `.claude/skills/`; works for kinds of code and domains that share a folder | Selection is judgment, not a rule; a project that needs a rule adds one to `CLAUDE.md`      |
| Path routes in a config file (review-routing 0.x) | Deterministic                                                                                                                                        | Needed Python 3.11 and a parser; a folder is not a kind of code; no step created the config |
| One reviewer agent per area                       | Each agent holds its own rules                                                                                                                       | Agents duplicate the builder skills; the review and the build drift apart                   |

## What the plugin contains

| Component             | Role                                                                                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `review` skill        | Orchestrator: range, intent, standards, checks, reviewer starts, summary, escape hand-off. Changes no code.                                                         |
| `reviewer` agent      | Read-only reviewer: `tools: Read, Grep, Glob, Bash, Skill` (Bash for read-only git only), `model: sonnet`, `effort: high`. Loads the standards it is given by name. |
| `record-escape` skill | Writes an escape as a checklist line in a standard, or as a file.                                                                                                   |
| `add-standard` skill  | Creates or extends a review standard (replaces `add-reviewer`).                                                                                                     |
| `inspect` skill       | Reads a project's own review instructions and proposes edits so they agree with the plugin.                                                                         |
| `migrate` skill       | Moves a project from an older version of the plugin (first: from review-routing 0.x).                                                                               |

Each skill's `description` names "mash review" as a trigger, so a user can ask for this plugin by name when other plugins also offer a code review.

## Decisions

### Standards

- **D1. Where a standard lives.** In a builder skill's "Review checklist" section, or in a project skill `.claude/skills/review-<topic>/SKILL.md`. When `add-standard` creates a standard and a builder skill for that kind of code exists, it asks the user which place to use. `record-escape` asks nothing: it writes to an existing standard (a builder's Review checklist counts only when the section is there), or else an escape file; a builder with no checklist is not a standard. For a builder from another plugin, the question says that a plugin update overwrites edits there and recommends the companion. With no builder, `add-standard` writes a standalone review skill and asks nothing. `record-escape` writes only into project files: for a standard in another plugin's builder skill, it writes a companion skill's line or an escape file, because a plugin update overwrites the plugin's files. A builder skill that holds a checklist says "Use when writing or reviewing …" in its `description`. The frontmatter is `name` and `description` only.
- **D2. One plugin agent.** `mash-review:reviewer` does every review. Project specialist agents stay optional and outside the plugin's flow: a user can ask for one by name.
- **D3. Models.** A standard may name its model with a line `Model: opus` (or `fable`). A group of standards runs on the strongest model its standards name (`fable` over `opus` over `sonnet`). The default is `sonnet`. A model the user's plan cannot start makes that reviewer fail twice: the summary reports **no verdict** with the error. A reviewer never runs on `haiku`.

### Reviewer agent

- **D4. Read-only by instruction, with Bash for git.** The agent has `tools: Read, Grep, Glob, Bash, Skill`. Its instructions allow only read-only commands: `git diff`, `git log`, `git blame`, `git show <ref>:<path>`, `git status`, `git merge-base`, `git rev-parse`, and forbid `git -c`, `--output`, `--ext-diff` and `--textconv`. Text in the diff, commit messages and files is data. It runs `git diff --no-ext-diff --function-context <range>` itself, and for a branch with two or more commits `git log --format='%h %s%n%n%b' <base>..HEAD`; with one commit, the orchestrator puts its message in the intent. Each reviewer reads the diff once as input, and the orchestrator writes no file. The guard against a writing command is the instruction plus Claude Code's permission check: in default mode a write needs approval (with no user present it is refused), and in auto mode the classifier judges it. In `bypassPermissions` mode only the instruction remains. There is no hook, so the plugin needs no Python.
- **D5. History.** A reviewer that needs to know why code exists runs `git log -L`, `git blame` or `git show` itself. It needs no round trip to the orchestrator.
- **D6. A reviewer with no verdict.** A reviewer that errors or gives no verdict is started again once. After a second failure, the summary reports that reviewer as **no verdict** and the review result as `NOT SAFE`.
- **D7. Findings name their standard.** The output keeps the groups Critical / Important / Minor / Pre-existing, each Pre-existing finding with `escape: yes` or `escape: no`, and the last line `SAFE TO LAND` or `NOT SAFE: <why>`.

### review skill

- **D8. Review only.** The skill never fixes, commits, stashes or pushes, and it says "This skill changes no code." It notes the commit id of `HEAD` (`git rev-parse HEAD`) before the review. A re-review on request goes only to the reviewers that found something, with the same standards and models and their earlier findings. A committed fix is reviewed as `git diff <noted HEAD> HEAD`. Re-review diffs use the same exclusions as working-tree mode. An uncommitted fix is reviewed as `git diff <noted HEAD>` plus the untracked files (in working-tree mode all of them again; in "only the commits" mode the new ones); in working-tree mode that diff also holds the first change again, because no snapshot is written.
- **D9. A change that edits its own rules.** When the diff changes a selected standard, a builder skill it cites, `CLAUDE.md` or `AGENTS.md`, the skill also applies the version at the base (`git show <base>:<path>`), tells the reviewer which standard changed, and names the change in the summary. The reviewer reports a removed or weakened check as Important.
- **D10. Plan mode.** The skill writes the review plan (range, intent, standards and why, reviewers and models, checks to run) It reads and runs read-only git only: it runs no check, starts no reviewer and writes no file.
- **D11. Uncommitted changes.** When files outside `.mash-review/` and `.claude/worktrees/` are changed or untracked, the skill does not ask first: it reviews everything in working-tree mode, and the summary starts with "Reviewed the commits plus the uncommitted files. Reply _only the commits_ or _commit first_ to review again." A mode the user named in the request wins. Asking first stopped `claude -p` sessions at the question with no review (eval case 07); reviewing first never blocks, and costs one review when the user wanted another mode. Working-tree mode reviews `git diff --no-ext-diff --function-context <base>` (the base against the working tree) and the untracked files that `git status --porcelain --untracked-files=all` lists, except `.mash-review/` and `.claude/worktrees/`. It writes no snapshot: in `claude -p` default mode, `git stash create` and a redirect to a file were refused in our test, and read-only git was not (see Verification).
- **D12. Check commands.** From `CLAUDE.md` or `AGENTS.md`. With none, the skill reads the project files (`package.json`, `Makefile`, `pyproject.toml` and similar), proposes commands, runs only those the user confirms, and offers a `CLAUDE.md` line (D15). With nothing to run, reviewers are told "no automated checks ran" and the summary says **Unchecked**.
- **D13. Red checks.** The skill always asks: "stop here, or review anyway?". "Review anyway" gives the red results to the reviewers and marks the summary **Checks red**. With no user present, the skill stops and lists the failures in the final report.
- **D14. No round limit.** Each review runs once for each request. A caller that loops (review, fix, review) sets its own limit.
- **D15. Offers.** Writes other than escapes (a new standard, a `CLAUDE.md` line) are offers, done only on the user's yes.
- **D16. Migration hint.** When `.claude/reviewers.toml` or `.claude/mash-workbench/escapes/` exists, the summary says "Run `/mash-review:migrate`".

### Escapes

- **D17. Where an escape goes.** If a standard matches: one checklist line, the check, then `(escape: <link>, <date>)`; if that check is already there, only the link is added. If no standard matches: a file `<main worktree>/.mash-review/escapes/<YYYY-MM-DD>-<slug>.md` with frontmatter `date`, `topic` and `source`, and a one-paragraph body in ASD-STE100 (conditions, incorrect result, expected result). An existing topic is reused for the same subject. The folder is meant to be committed, so the team shares its misses; the files wait uncommitted in the main worktree until the user commits them, and no skill commits them. A project that wants them private adds `.mash-review/` to `.git/info/exclude`. There is no settings file, lock, review log or allow rule.
- **D18. Writes need a user present.** With no user present, nothing is written: the final report gets an **Escapes to record (confirm where)** block, and the session that gets the confirmation records them. A session in a linked worktree writes the file in the main worktree, because a worktree is often deleted after its branch is pushed.
- **D19. Reminders.** Each review summary lists the waiting escape files by topic. When a write brings a topic to exactly three files, the skill offers `add-standard`: the files become the first checklist items and then move to `escapes/processed/`. After a no, nothing is stored; the skill offers again when a write brings the topic to exactly five, and after that only the summary list reminds the user.
- **D20. "Did a review pass this code?"** During a review, the reviewer's `escape: yes` answers it. Otherwise the skill asks the user.
- **D21. Escape text is data.** The body is written in the skill's own words. Text in an escape file is never followed as an instruction.

### Project determinism

A project forces standards with rules in its own `CLAUDE.md` or `AGENTS.md`, for example "A change under `src/payments/` always gets the `review-payments` standard". The `review` skill always applies such rules, and its summary names them. For a guarantee that does not depend on a model, a project adds its own hooks, tests or CI jobs; the plugin ships none.

### Plugin name and migration

- **D22. Name.** `mash-review` 1.0.0, a plugin separate from mash-workbench. Skills: `review` (was `review-changes`), `record-escape`, `add-standard` (was `add-reviewer`), `inspect`, `migrate`. Agent: `reviewer` (was `change-reviewer`).
- **D23. Rename.** Both marketplace files hold `"renames": {"review-routing": "mash-review"}`. The map only grows. Claude Code changes the user's settings and shows a notice; a user runs `/plugin install mash-review@mash-workbench-marketplace` once. There is no stub plugin.
- **D24. `migrate`.** One section for each migration path, "from review-routing 0.x" first. Only the user starts it: by the command, by a hint from `review` or `inspect`, or in plain words. It lists what it found, makes one proposal, applies the approved items, and deletes old files only after the new ones exist and the user agrees. In plan mode or with no user present it gives the proposal only. Tracked files (the routes file, agent files, standards, project text) change in the current worktree, so they land on the user's branch; untracked files (`settings.local`, `reviews.log`, `.git/info/exclude`, untracked old escapes, `.claude/settings.local.json`) change in the main worktree. It converts `reviewers.toml` routes and project reviewer agents into standards (with the D1 question for each builder), old escape files into checklist lines or new escape files, and old skill names in project text. It also removes the allow rules and `env` entries that name review-routing scripts, including the rules with a leading wildcard from review-routing 0.4.0 to 0.5.0, which approve any command that mentions the script name.
- **D25. Inspect line.** `inspect` and `migrate` offer the project line "For code reviews, use the mash-review plugin's `review` skill".

## Diagrams

### 1. System map

```mermaid
flowchart TB
  subgraph project["Consumer project (the team owns all of it)"]
    rules["CLAUDE.md / AGENTS.md: check commands, required standards"]
    standards[".claude/skills/review-*/SKILL.md: companion or standalone standards + escape lines"]
    builders["builder skills: project or other plugins; project ones may hold a Review checklist"]
    escfiles["main worktree .mash-review/escapes/*.md: escapes with no standard yet"]
    hooks["optional project hooks, tests, CI"]
  end

  subgraph plugin["mash-review plugin: instructions only"]
    review["review skill: orchestrator"]
    reviewer["reviewer agent: Read, Grep, Glob, Skill; Bash for read-only git"]
    record["record-escape skill"]
    add["add-standard skill"]
    inspect["inspect skill"]
    migrate["migrate skill"]
  end

  rules -->|"check commands, required standards"| review
  hooks -.->|"project's own guarantees"| review
  standards -->|"descriptions"| review
  builders -->|"descriptions with 'or reviewing'"| review
  review -->|"range or working-tree mode, intent, check results, standard names, model"| reviewer
  reviewer -->|"git diff, log, blame, show"| git[("git repository, read only")]
  reviewer -->|"loads by name"| standards
  standards -->|"cite"| builders
  reviewer -->|"loads the cited skill"| builders
  reviewer -->|"findings with standard + verdict"| review
  review -->|"escape: yes findings"| record
  record -->|"checklist line"| standards
  record -->|"checklist line"| builders
  record -->|"no matching standard"| escfiles
  escfiles -->|"3 per topic: offer"| add
  add -->|"creates or extends"| standards
  add -->|"Review checklist section"| builders
  inspect -->|"proposed edits, approved only"| rules
  migrate -->|"reviewers.toml + old agents → standards"| add
  migrate -->|"old escapes → lines or files"| record
```

### 2. Main review flow

```mermaid
flowchart TD
  start(["Review requested"]) --> mode{"Plan mode?"}
  mode -->|yes| planonly["Write the review plan: range, intent, standards and why, reviewers and models, checks to run. Read only: no check, no reviewer, no write."]
  mode -->|no| dirty{"Uncommitted changes outside .mash-review/ and .claude/worktrees/?"}
  dirty -->|yes| named{"Did the request name a mode?"}
  named -->|no| wt["Working-tree mode: base vs the working tree, plus untracked files; the summary offers only the commits or commit first"]
  named -->|"only the commits"| fixbug
  wt --> fixbug
  dirty -->|no| fixbug{"Does the change fix a bug a review passed?"}
  fixbug -->|yes| rec0["record-escape"]
  fixbug -->|no| range["Range: base...HEAD, or base vs the working tree. Note HEAD. Intent: commits, PR text or the user"]
  rec0 --> range
  range --> select["Select standards by description; add the standards project rules require"]
  select --> any{"Any standard selected?"}
  any -->|no| general["One reviewer with the general checklist only; offer add-standard in the summary"]
  any -->|yes| group["Group standards into reviewers by size and model; each also applies the general checklist"]
  general --> cmds
  group --> cmds{"Check commands in CLAUDE.md or AGENTS.md?"}
  cmds -->|no| propose["Propose commands from project files; run only the ones the user confirms; none: mark Unchecked"]
  cmds -->|yes| checks["Run the project check commands once"]
  propose --> checks
  checks --> gate{"All green?"}
  gate -->|no| red{"Ask: stop here, or review anyway?"}
  red -->|"stop, or no user"| stopred(["Summary or final report: the failing checks; no reviewer started"])
  red -->|"review anyway"| dispatch
  gate -->|"yes, or no commands: mark Unchecked"| dispatch["Dispatch every reviewer in one message"]
  dispatch --> collect["Collect findings and verdicts"]
  collect --> noverdict{"A reviewer errored or gave no verdict?"}
  noverdict -->|"yes, first time"| again["Dispatch that reviewer again"] --> collect
  noverdict -->|"yes, second time"| nov["Report it as no verdict; result NOT SAFE"] --> esc
  noverdict -->|no| esc{"Pre-existing with escape: yes?"}
  esc -->|yes| rec4["record-escape"]
  esc -->|no| summary
  rec4 --> summary["Summary in the terminal: verdicts, findings with their standard, checks or Unchecked or Checks red, Pre-existing, escapes recorded or waiting, offers, migration hint"]
  summary --> end1(["Stop. The session fixes with builder skills only when the user asks"])
```

### 3. Review, fix (outside the plugin), re-review

```mermaid
sequenceDiagram
  actor U as user
  participant S as session
  participant RV as review skill
  participant R as each reviewer
  participant B as builder skills
  U->>S: review (or review and fix)
  S->>RV: run
  RV->>RV: note HEAD
  RV->>R: range or working-tree mode, intent, check results, standard names, model
  R->>R: run read-only git: diff, log, blame, show
  R->>R: load the named standards and the builder skills they cite
  R-->>RV: findings (each with its standard) and verdict
  RV-->>S: summary, escapes recorded
  Note over S: "review" only: stop here
  S->>B: for each finding, the builder skill its standard names
  B-->>S: fixes (commits only when the user asked)
  S->>RV: re-review
  RV->>R: only to the reviewers that found something: diff from the noted HEAD, earlier findings, same standards and model
  R-->>RV: findings and verdict
  Note over S,RV: No round limit in the plugin; a looping caller sets its own
```

### 4. Escape loop

```mermaid
flowchart TD
  found(["A bug in code a review passed: user, CI, review comment, or escape: yes finding"]) --> mode{"Plan mode?"}
  mode -->|yes| describe["Say where each escape would go; write nothing"]
  mode -->|no| user{"A user can answer now?"}
  user -->|no| report["Write nothing. Final report block: Escapes to record (confirm where)"]
  report -.->|"user confirms later, in any session"| reviewed
  user -->|yes| reviewed{"Did a review pass this code? escape: yes answers it; else ask the user"}
  reviewed -->|no| skip["Record nothing; say so"]
  reviewed -->|yes| behavior{"Behavior bug: wrong result, lost data, guard bypassed?"}
  behavior -->|no| skip
  behavior -->|yes| match{"Which existing standard covers it? Match by description"}
  match -->|found| dup{"Its checklist already has this check?"}
  dup -->|yes| link["Add the link to the existing item"]
  dup -->|no| item["Add a checklist line: the check, then the link and date"]
  match -->|none| file["Write main worktree .mash-review/escapes/date-slug.md with date, topic, source"]
  file --> count{"This write brings the topic to exactly 3 or 5 files?"}
  count -->|no| waits["Listed as waiting in every review summary"]
  count -->|yes| offer{"Create a standard from them with add-standard?"}
  offer -->|no| waits
  offer -->|yes| builder{"A builder skill exists for this kind of code?"}
  builder -->|no| create["New review skill; the files become its first items; move them to processed/"]
  builder -->|yes| where{"Ask: Review checklist in the builder skill, or a companion review skill?"}
  where -->|builder| inbuilder["Add the section and the items; description gains 'or reviewing'; move files to processed/"]
  where -->|companion| create
```

### 5. Anatomy of a review standard

```markdown
---
name: review-angular-components
description: Use when reviewing a change that adds or edits an Angular component, its template, or its inputs and outputs
---

# Review: Angular components

Load the `acme-angular:component` skill and check the change against it.

Model: sonnet

## Project checks

- A component that subscribes to an observable unsubscribes, with `takeUntilDestroyed` or the `async` pipe. (escape: https://github.com/acme/shop/pull/12, 2026-11-23)

## Not checked here

- Formatting and import order: the formatter and the linter enforce them.
```

A "Review checklist" section in a builder skill holds the same "Project checks" and "Not checked here" lists under its own heading, and the builder's `description` starts "Use when writing or reviewing …".

## Contracts

### Reviewer prompt

The orchestrator gives each reviewer, in this order:

1. The range to review (`<base>...HEAD`), or working-tree mode with `<base>` and the diff command with its exclusions (see "Uncommitted changes"), or for a re-review the diff command from D8.
2. The base, so the reviewer can run `git log <base>..HEAD` when the branch has two or more commits.
3. The intent, in one to three sentences.
4. The check results ("suite: 412 passed; lint clean"), or "no automated checks ran", or the red results with **Checks red**.
5. The standards to apply, by skill name, and why each one was selected. A standard that the diff itself changes is named as such (D9). The general checklist always applies; a review with no selected standard gets none.
6. In working-tree mode, the untracked files to read.
7. For a re-review, the reviewer's earlier findings.

### Reviewer output

Findings under **Critical** (data lost, a guard bypassed, a wrong result shipped), **Important** (a wrong result a later change will trust, a missing test for a new branch) and **Minor**. Each finding has `path:line`, the standard it broke (`general` for the agent's own checklist), a failure scenario and a one-line fix. Then **Pre-existing**, each with `escape: yes` or `escape: no`. Then exactly one last line: `SAFE TO LAND` when there are no Critical and no Important findings, else `NOT SAFE: <why>`.

### Escape file

```text
---
date: 2026-11-23
topic: angular-subscriptions
source: https://github.com/acme/shop/pull/12#discussion_r222
---

When a component subscribes to a store selector in ngOnInit, the subscription stays after the component is destroyed. The component must unsubscribe when it is destroyed.
```

`source` is left out when there is no link. The file name is `<date>-<slug>.md`; when the name exists, `-2`, `-3` and so on go before `.md`.

### Summary

In the terminal only: each reviewer's verdict and standards, the findings with their standard, the checks (or **Unchecked**, or **Checks red**), the Pre-existing findings, the escapes recorded or waiting by topic, the offers, and the migration hint. With no user present the same content goes in the final report, plus the **Escapes to record (confirm where)** block.

## Out of scope and known effects

- **mash-workbench.** It keeps its scripts and its Python for now; a separate change moves it to the same rules. Until then, `AGENTS.md` and mash-workbench disagree, and `forge` finds no escapes, because it reads the old escape files of review-routing.
- **Copilot CLI.** It reads skills from `.claude/skills`, so project standards work there. The plugin itself is not tested in Copilot CLI.
- **No round limit, no review log.** "Did a review pass this code?" has no record outside the session; the user answers it when the reviewer did not.

## Verification

- `bash scripts/check.sh` and `uvx pre-commit run --all-files`.
- `claude plugin eval` cases in `evals/mash-review/` (outside the plugin, so they do not ship; `bash scripts/eval-mash-review.sh` runs them on a copy). The harness runs each case as `claude -p` in `dontAsk` mode, so the cases cover the paths with no user present: a general review with no standards; a standard selected by description; a standard required by a `CLAUDE.md` rule; a red check stops the review; the escape block; a migration proposal; a prompt that does not say whether anyone can answer, on a dirty tree (working-tree mode, no question). Each grants `Write` and `Edit` and grades that neither is used.
- By hand, because they need plan mode or a user's answer: plan mode writes nothing; the uncommitted-changes question; red checks with a user (the question); an escape into an existing standard; an escape file when no standard matches; the 3-file offer and `add-standard`; an applied migration.
- The eval runner grants the git commands with `--allow-tools`, so the cases do not show that a session with no allow rules can run them; that rests on the test below, which covered `git diff`, `git log`, `git blame`, `git status` and `git show`, not `git merge-base`, `git rev-parse` or `git worktree list`, nor the pathspec forms.
- Verified on Claude Code 2.1.330 with `claude -p` in default permission mode (2026-11-23): in the main session and in a subagent, `git diff`, `git log`, `git blame`, `git status` and `git show <ref>:<path>` ran with no prompt; a redirect to a file, `git diff --output`, `git stash create`, `touch`, and a subagent's `Read` of a file in `/tmp` were refused. This is why D4 gives the reviewer Bash and why working-tree mode writes no snapshot.
- A manual run in a scratch project with `claude --plugin-dir plugins/mash-review`, on a host with no Python 3.11: a full review, a re-review after a fix, and `/mash-review:migrate` on a copy of a review-routing project.
