# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p docs/mash
printf '# Tooling backlog\n\n- [ ] 2026-11-02 · script · Rebuild the search index — done by hand twice\n' > docs/mash/tooling-backlog.md
git add -A
git commit -q -m "project with the mash-workbench 0.x default backlog"
