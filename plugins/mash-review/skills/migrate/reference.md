# migrate reference

## Inventory

From review-routing 0.x, in the main worktree:

- `.claude/reviewers.toml`: `default_reviewer`, `default_model`, `allow_default`, and each table: `[[routes]]` and `[[fallbacks]]` (`pattern`, `reviewers`, `reason`), `[[changed_lines]]` (`path_pattern`, `line_pattern`, `reviewers`), `[[mirrors]]`, `[[model_rules]]` (`reviewer`, `model`, and its conditions), `[[import_guards]]`. `[[expect]]` entries are routing tests: they go with the file;
- `.claude/agents/*.md` that a route names: each reviewer's checklist;
- the escapes folder: `.claude/mash-workbench/escapes/*.md`, or the folder that `REVIEW_ROUTING_ESCAPES` or the last `escapes=` line of `.claude/mash-workbench/settings.local` or `settings` names, with `processed/`;
- the review-routing keys in `.claude/mash-workbench/settings` and `settings.local` (`escapes`, `escapes.threshold`, `declined.*`), and `reviews.log` with its `.git/info/exclude` line. The mash-workbench plugin keeps its own keys (`backlog`) in the same files;
- allow rules in `.claude/settings.local.json` and `.claude/settings.json` that name `review-routing`, or `escape-add.sh`, `escape-migrate.sh`, `review-log.sh` or `mash-settings.sh` in a `review-routing` folder, and every rule with a `*` before one of those four script names, in any settings file of the project (keep the mash-workbench rule for `backlog-add.sh`);
- `REVIEW_ROUTING_ESCAPES` in the `env` blocks of `.claude/settings*.json`;
- text in `CLAUDE.md`, `AGENTS.md`, `.claude/` and docs that names `review-routing`, `review-changes`, `add-reviewer`, `route`, `reviewers.toml` or `change-reviewer`.
