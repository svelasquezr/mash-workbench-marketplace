# migrate reference

## Inventory

From review-routing 0.x, in the main worktree:

- `.claude/reviewers.toml`: `default_reviewer`, `default_model`, `allow_default`, and each table: `[[routes]]` and `[[fallbacks]]` (`pattern`, `reviewers`, `reason`), `[[changed_lines]]` (`path_pattern`, `line_pattern`, `reviewers`), `[[mirrors]]`, `[[model_rules]]` (`reviewer`, `model`, and its conditions), `[[import_guards]]`. `[[expect]]` entries are routing tests: they go with the file;
- `.claude/agents/*.md` that a route names: each reviewer's checklist;
- the escapes folder: `.claude/mash-workbench/escapes/*.md`, or the folder that `REVIEW_ROUTING_ESCAPES` or the last `escapes=` line of `.claude/mash-workbench/settings.local` or `settings` names, with `processed/`;
- the review-routing keys in `.claude/mash-workbench/settings` and `settings.local` (`escapes`, `escapes.threshold`, `declined.*`), and `reviews.log` with its `.git/info/exclude` line. The mash-workbench plugin keeps its own keys (`backlog`) in the same files;
- allow rules in `.claude/settings.local.json` and `.claude/settings.json` that name `review-routing`, or `escape-add.sh`, `escape-migrate.sh`, `review-log.sh` or `mash-settings.sh` in a `review-routing` folder, and every rule with a `*` before one of those four script names, in any settings file of the project (keep the mash-workbench rule for `backlog-add.sh`);
- `REVIEW_ROUTING_ESCAPES` in the `env` blocks of `.claude/settings*.json`;
- text in `CLAUDE.md`, `AGENTS.md`, `.claude/` and docs that names `review-routing`, `review-changes`, `add-reviewer`, `[[routes]]`, `reviewers.toml` or `change-reviewer`.

## Proposal

One item each:

- **Reviewer agent → standard.** For each project reviewer agent: a standard with its checklist, made with the `add-standard` steps (its question about a builder skill included). The patterns of its `routes` and `fallbacks`, and the `path_pattern` and `line_pattern` of its `changed_lines`, become words in the description; a path that must always get the standard becomes a proposed `CLAUDE.md` rule. A `model_rules` entry for it with `opus` or `fable` becomes `Model: opus` (or `fable`); `default_model` was for the plugin's own reviewer, so it goes to no standard: name it in the report; the agent file's `model:` line is the fallback. Then delete the agent file.
- **Escape files.** Each old file (`area`, `class`, body, `source`): a checklist line in the standard that now covers it, or a new file in `<main worktree>/.mash-review/escapes/` with `topic` from its area and class. Files in `processed/` are history: leave them, or delete them with the old folder.
- **Old entries to delete:** `reviewers.toml`; the review-routing keys in the settings files; `reviews.log` and its exclude line; the old escapes folder once it is empty. Delete a settings file, and the `settings.local` exclude line, only when no key is left in it: mash-workbench reads them and trusts `settings.local` only while that exclude line exists.
- **Allow rules and `env` entries to remove.** They still approve the old scripts that Claude Code keeps in its plugin cache. A rule with a wildcard before the script path (`Bash(bash */review-routing/*escape-add.sh*)`, from 0.4.0 to 0.5.0) approves any command that mentions the name: it must go first. Tell the user to check other settings files they copied rules to (`~/.claude/settings.json`, other worktrees).
- **Text to rewrite:** `review-changes` → `mash-review:review`; `add-reviewer` → `mash-review:add-standard`; `review-routing:change-reviewer` → `mash-review:reviewer`; routes and `reviewers.toml` → standards; the line "For code reviews, use the mash-review plugin's `review` skill".
