---
name: inspect
description: Use when the review-routing plugin is installed in a project that already has its own review instructions (CLAUDE.md, AGENTS.md, memory, plans), or when reviews there don't follow review-pr - reviewers dispatched directly, Haiku reviewers, models picked by hand
---

# Ready a project for review routing

A project's own instructions outrank a plugin's skills, so an old review rule in them keeps winning over the routing. This skill finds those rules and proposes rewrites. The owner approves each one before anything is edited: never run it headless. It never creates an agent file or a `.claude/reviewers.toml`: specialists come only from the add-reviewer skill.

**Dry run**: steps 1 and 2 without edits: show the proposals and stop.

Read "Plugin rules" in `<this skill's base directory>/reference.md` before step 1.

## Steps

1. **Conflicts.** Grep CLAUDE.md and AGENTS.md (nested too) and, where they exist, `.claude/memory/`, the auto-memory folder (`~/.claude/projects/<slug>/memory/`; its edits don't ship), `.claude/plans/`, plan and spec docs and `.claude/agents/` for the listed words, reading hits in context. For each instruction that contradicts a rule: `file:line`, the rule, the text, a proposed rewrite. A missing test, lint or format command is a gap: propose the line. Show every proposal at once; apply only approved ones.
2. **Improvised specialists.** List the focus areas the project briefs reviewers on by hand ("Review Focus" sections, design-review briefs, extra reviewers a PR named). Each is an add-reviewer candidate ("user names an expensive area"): offer it, create none.
3. **Ship** the approved edits as one pull request, reviewed with review-pr.

## Common mistakes

| Mistake | Instead |
|---|---|
| "The hook blocks Haiku, the text can stay" | Rewrite it: sessions follow the text first |
| Opus or Fable sizing text called a conflict | Only text naming Haiku or replacing `route --models` |
| A project's own merge strategy called a conflict | Merge flow belongs to the project |
| Writing the specialist now | Offer add-reviewer; create nothing |
