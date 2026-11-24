# shellcheck shell=bash
set -e
git init -q -b main .
# The fresh entries are dated a few days before the run, so they never become stale (GNU date; the eval sandbox is Linux).
recent1=$(date -d '-4 days' +%F)
recent2=$(date -d '-3 days' +%F)
mkdir -p docs/mash
cat > docs/mash/tooling-backlog.md <<B
# Tooling backlog

- [ ] $recent1 · script · Check the lockfile matches the CI Python version — CI failed twice on an unpinned version
- [ ] $recent2 · unsure · Lockfile and CI Python version drift — same failure again on another branch
- [ ] 2025-01-10 · hook · Format SQL migrations on save — two reviews asked for it
- [ ] skill · Write the weekly status note — done by hand every Friday
- [x] 2026-09-02 · hook · Block edits to generated files → built: .claude/hooks/no-generated.sh
B
git add -A
git commit -q -m "project with a tooling backlog"
