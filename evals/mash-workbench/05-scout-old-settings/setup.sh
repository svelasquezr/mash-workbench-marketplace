# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p .claude/mash-workbench docs
printf '# Tooling backlog\n\n- [ ] 2026-11-02 · script · Rebuild the search index — done by hand twice\n' > docs/tooling-backlog.md
printf 'backlog=docs/tooling-backlog.md\n' > .claude/mash-workbench/settings
git add -A
git commit -q -m "project on mash-workbench 0.3.0"
