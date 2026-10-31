---
name: scout
description: Use when you notice yourself repeating a multi-step procedure, when the user corrects the same thing a second time, when a manual check could be automated, or when a memory you are about to save describes a procedure
---

# Tooling candidate

Capture, don't build. The current task comes first.

1. Pick the most deterministic form that fits:
   - **hook**: a rule that must always hold (block, format, validate)
   - **script**: a procedure with no judgment
   - **skill**: judgment is needed; it calls scripts for the mechanical steps
   - **agent**: a review that needs a separate context
   - **mcp**: access to an external system

   Use `unsure` if it's unclear.
2. Run `bash <this skill's base directory>/backlog-add.sh "<repo-root>" <form> "<short title>" "<why: what repeated or what went wrong>"`, where `<repo-root>` is the literal path `git rev-parse --show-toplevel` prints (run it on its own, not inside `$( )`, which some permission setups refuse). Outside a git repository use the project folder.
   - Exit 3 means the project has no backlog yet, and nothing was written. Ask the user, in one question, where to keep it: `docs/mash/tooling-backlog.md`, another file, or nowhere. Re-run with `--create` or `--file <path>`, and offer to add the new file to `.gitignore` (recommend committing it: an ignored backlog holds only this user's entries). For another file or nowhere, offer to add `{"env": {"MASH_WORKBENCH_BACKLOG": "<path, or off>"}}` to `.claude/settings.local.json` (only this user) or `.claude/settings.json` (the whole project), so later sessions don't ask again.
   - A message that the backlog is off: say nothing and continue the task.
3. Tell the user in one line (`"Noted for /forge: <title>"`), then continue the task. If the script also printed `near duplicate of: <title>`, add `"(similar to <title>)"` to that line; `/forge` merges the two.

Where it will go once promoted (decided in `/forge`, not now): if it's useful outside this project → a plugin or config repository shared across projects; if it's project-specific agent tooling → the project's own agent folder (`.claude/` in Claude Code); if it's project domain logic → project code.
