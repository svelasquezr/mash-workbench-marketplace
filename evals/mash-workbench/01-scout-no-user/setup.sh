# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p .mash-workbench tests
printf '# Tooling backlog\n\n- [ ] 2026-11-20 · hook · Block edits to generated files — edited dist/ by hand twice\n' > .mash-workbench/tooling-backlog.md
printf '0.4.1\n' > VERSION
printf '#!/usr/bin/env bash\necho ok\n' > tests/run.sh
git add -A
git commit -q -m "project with a tooling backlog"
