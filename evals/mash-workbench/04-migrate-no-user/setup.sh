# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p .claude/mash-workbench docs/tooling
printf '# Tooling backlog\nrepo: github.com/acme/shop\n\n- [ ] 2026-11-20 · script · Seed the test database — done by hand three times\n' > docs/tooling/backlog.md
printf 'backlog=docs/tooling/backlog.md\nescapes=docs/escapes\n' > .claude/mash-workbench/settings
printf '# Project rules\n\nRun bash tests/run.sh before each commit.\n' > CLAUDE.md
git add -A
git commit -q -m "project on mash-workbench 0.3.0"
printf '{"permissions": {"allow": ["Bash(bash /fake-home/.claude/plugins/cache/mash-workbench-marketplace/mash-workbench/0.3.0/skills/scout/backlog-add.sh *)", "Bash(npm test)"]}}\n' > .claude/settings.local.json
printf '.claude/mash-workbench/settings.local\n.claude/settings.local.json\n' >> "$(git rev-parse --git-common-dir)/info/exclude"
