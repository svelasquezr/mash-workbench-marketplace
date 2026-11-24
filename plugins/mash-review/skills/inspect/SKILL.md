---
name: inspect
description: Use when the mash-review plugin is installed in a project that already has its own review instructions (CLAUDE.md, AGENTS.md, memory, plans, reviewer agents), or when reviews there do not follow the mash review skill - reviewers started by hand, Haiku reviewers, several code-review plugins answering
---

# Ready a project for mash review

A project's own instructions outrank a plugin's skills, so an old review rule in them keeps winning. This skill finds those rules and proposes rewrites. The user approves each one before anything is edited. In plan mode, or with no user present, it shows the proposals and stops. It creates no standard itself: it offers `add-standard`.

## Steps

1. **Old plugin.** `.claude/reviewers.toml`, or `.claude/mash-workbench/escapes/` in the main worktree: say "Run `/mash-review:migrate` first", and stop. Instructions that tell a session to use `review-changes` or `add-reviewer` are conflicts for step 2; history (changelogs, ADRs) is not.
2. **Conflicts.** Read `CLAUDE.md` and `AGENTS.md` (nested ones too) and, where they exist, `.claude/memory/`, `.claude/plans/`, plan and spec docs, and `.claude/agents/`. For each instruction that breaks a rule below: `file:line`, the rule, the text, and a proposed rewrite. Show every proposal at once; apply only the approved ones.
3. **Gaps.** No test, lint or format command named: propose the line from the project files. No line that names the review skill: propose "For code reviews, use the mash-review plugin's `review` skill" (it keeps other code-review plugins from answering).
4. **Standards to offer.** List the areas the project briefs reviewers on by hand ("Review focus" sections, design-review briefs, reviewer agents) and the builder skills with no "Review checklist". Each is an `add-standard` candidate: offer it, create none.
5. **Hand-off.** The user commits the approved edits. Offer a mash review of them.

## Rules

| Rule                                                | Text that breaks it                                                                                      |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| The `review` skill starts the reviewers             | "dispatch the X reviewer", "run these agents in parallel", a hand-made reviewer list                     |
| A reviewer never runs on Haiku                      | `haiku`, "a cheap model for reviews" in review text                                                      |
| A review changes no code                            | "review and fix", "fix the findings and commit", "auto-fix" as a review step                             |
| Checks run once, before the reviewers               | "reviewers run the tests", a reviewer brief that runs the suite                                          |
| Escapes go to a standard or `.mash-review/escapes/` | another escape ledger or a rule to put escapes in `CLAUDE.md`                                            |
| Standards are skills with a `description`           | review rules only in an agent file or a long `CLAUDE.md` section: offer to move them with `add-standard` |

Text that sizes a model up (Opus for security) is not a conflict. A rule the user wants to keep stays: the project's text outranks the plugin.
