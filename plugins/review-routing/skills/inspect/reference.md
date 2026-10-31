# inspect reference

Detail the inspect skill points to. Commands run from the project's repository; `route` means `python3 <this skill's base directory>/../review-pr/reviewers-for-change.py`. Text proposed for the project names the script as review-pr's `reviewers-for-change.py --models`, because a project reader doesn't know the alias.

## Plugin rules

Project text that contradicts one of these is a conflict. A session reads CLAUDE.md, memory and the plan it executes before any skill, so a contradicting sentence wins there even when the plugin enforces the rule elsewhere.

| Rule | A conflict | Not a conflict |
|---|---|---|
| Reviewers are never Haiku, fix-round re-checks included | text that puts a re-check, a quick review or a fix-round verification on Haiku | Haiku for a builder session or a research agent that judges nothing |
| A code change is reviewed through the review-pr skill | text that sends a session straight to a reviewer agent (a named reviewer, or a general-purpose agent asked to review the PR) | design reviews of specs or plans: they are outside review-pr's scope |
| A reviewer's model comes from `route --models` (or the agent file), never from project text | sizing text the session applies instead of `route --models` | sizing that agrees with the `model_rules` policy (Fable for design, Opus for substantial logic, Sonnet otherwise) and defers to `route --models` |
| Reviewer agent files are read-only and keep the verdict line | a reviewer agent file with Edit or Write in `tools:`, with no `tools:` line (it then gets every tool), or without the `SAFE TO LAND` verdict line | agents that are not reviewers |
| CLAUDE.md names the test, lint and format commands (review-pr's deterministic gate runs them) | a missing command: a gap, so propose the line to add rather than a rewrite | commands named in a doc CLAUDE.md links to |
| Merge flow (strategy, branch names, labels, PR text) | none: the plugin's defaults give way to the project | text that names its own merge strategy, base branch, labels or PR format |

A reviewer agent is a file in `.claude/agents/` that `.claude/reviewers.toml` names or, in a project with no config yet, one whose name contains "reviewer" or whose text ends with the `SAFE TO LAND` verdict line.

Grep case-insensitively (`grep -rni`) for: `haiku`, `review`, `re-check`, `recheck`, `subagent_type`, `change-reviewer`, `general-purpose`, `model`, `effort`. Skip other checkouts (`.claude/worktrees/`, vendored copies). Read each hit with its paragraph: a sizing list often names Haiku three lines below the word "review".

- The plugin's PreToolUse hook (`hooks/haiku-reviewer-guard.py`) already refuses a reviewer launched on Haiku. Project text that asks for one is still a conflict: the hook sees a reviewer only through its name or its prompt's verdict words, and a refused dispatch costs a round. Likewise look for text that tells reviewers to `git checkout` or `gh pr checkout` the PR branch: the plugin's `hooks/reviewer-guard.py` refuses those from the plugin's reviewers (its own agents and the agents `.claude/reviewers.toml` names) in a real repo, so the rewrite points them to `git show <ref>:<path>`, `git diff` or `git archive <ref> | tar -x -C "$(mktemp -d)"`.
- Text that tells a session how to run a code review without naming review-pr (for example, a line saying to start a reviewer agent at each review gate) is a conflict of the second rule: the rewrite names review-pr.
- A sizing list the session applies to pick a reviewer's model replaces `route --models`, even when most of its items agree with the policy: rewrite the whole list as a pointer to the script. A list that only explains the policy and defers to the script loses just its Haiku item.
- One command that runs tests, lint and type checks together names them all.
- A rewrite keeps the owner's intent and drops only the contradiction. A list mapping each kind of review to a model, with Haiku for re-checks at its end, becomes: "Reviewers and their models come from the review-pr skill (its `reviewers-for-change.py --models`); a fix-round re-check runs on the model the reviewer started on, never Haiku."
- The same rule often sits in several places (CLAUDE.md, a memory, each milestone plan). List every copy; a plan whose work has all landed (its PRs merged, its task issues closed; checkboxes are often left unticked) is a record, not an instruction, so note it and propose no rewrite. A plan with tasks still open is live. Rewrite every restatement too: a memory's `description` and its index line in `MEMORY.md`.
- Memory and CLAUDE.md belong to the owner: show the whole list first, then apply only what they approve. An approved edit to the repository's `.claude/memory/` ships in the PR; one to the user-level auto-memory (`~/.claude/projects/<slug>/memory/`) is made in place and doesn't, so say so.
