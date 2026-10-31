---
name: forge
description: Use when the project's tooling backlog has open candidates to triage, when the user asks what repeated work is worth automating, or when they invoke /forge
---

# Forge tooling candidates

`<dir>` is this skill's base directory (shown when the skill loads, wherever the plugin is installed). The `scout` skill's scripts are next to it, in `<dir>/../scout/`.

1. Read the backlog, the file `bash <dir>/../scout/backlog-path.sh <repo-root>` prints (exit 3 or 4: the project has none; go on with the other sources), its open items (`- [ ]`) and its stale entries: `bash <dir>/../scout/backlog-stale.sh <repo-root>`. Each stale or undated entry gets a row: build it, or drop it (mark it `- [x]` with "→ dropped: <why>"). Entries that describe the same candidate share one row. Then collect candidates from these sources:
   - this conversation: procedures repeated two or more times, corrections the user made more than once, manual checks, and memories saved this session (if the tool keeps memories) that describe a procedure;
   - earlier sessions: `python3 <dir>/../../scripts/past-friction.py --project <repo-root>`. It prints corrections and Bash command sequences seen in 2 or more sessions of the last 14 days (`--days N` for more). Each line is a lead, not a candidate: keep it only when it names repeatable work;
   - optional, when the review-routing plugin is installed and `docs/review-escapes.md` exists: `bash <escapes-dir>/escapes-report.sh <repo-root>`, where `<escapes-dir>` is the base directory of the `review-routing:add-reviewer` skill (shown when it loads). It counts each distinct link once per area; an area it marks "add a reviewer" is a reviewer candidate (form: agent; the add-reviewer skill builds it). Without that plugin, count distinct links per area, never lines: two or more make a candidate.
2. Present ONE table with one row per candidate: form (hook > script > skill > agent > mcp, deterministic first), location (a plugin or config repository shared across projects, when useful beyond this project; project-level agent tooling if project-specific; project code if domain logic), reasoning, rough size, **pros and cons**. Recommend which ones to build.
3. Ask the user which to build (multi-select). Build nothing unapproved.
4. Build each approved item test-first:
   - scripts and hooks get tests in the target repo's test suite;
   - skills follow superpowers:writing-skills when that plugin is installed (optional);
   - plugin changes bump the plugin `version`, pass the target repo's own test command, and pass `claude plugin validate`.
5. Mark each built item `- [x]` in the backlog with a pointer to where it now lives. If the tool keeps memories and one was promoted, rewrite that memory as a one-line pointer to the tool.
6. Leave the changes uncommitted unless the project's own rules say to commit them. Tell the user which repositories were changed, and which need a commit, a push or a plugin update to reach other projects.
