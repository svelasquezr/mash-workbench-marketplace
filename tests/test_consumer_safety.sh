# shellcheck shell=bash
# What an allow rule pre-approves must stay safe on the user's machine: a write goes only to the repository the session
# works in; the review log is this clone's own; text from files that others can commit reaches the terminal without
# control characters; no network call on an old git; no allow rules where the checks are untested (Windows).
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
rr="$PWD/plugins/review-routing"
mw="$PWD/plugins/mash-workbench"
settings_script="$rr/scripts/mash-settings.sh"
area=$(mktemp -d "$HOME/.consumer-safety-test.XXXXXX"); trap 'rm -rf "$area"' EXIT
case "$(cd "$area" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
area=$(cd "$area" && pwd -P)
temporary_directory="$area"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES MASH_WORKBENCH_BACKLOG
new_repository() {
  git init --quiet "$1"; printf 'a\n' > "$1/a"; git -C "$1" add a; git -C "$1" commit --quiet -m "feat: a"
  printf 'b\n' >> "$1/a"; git -C "$1" commit --quiet -am "fix: a"
}
esc=$'\033'
no_escape_byte() { if [[ "$1" == *"$esc"* ]]; then echo "  an escape byte reached the output ($2)"; exit 1; fi; }

# 1. A write goes only to the repository of the current folder.
a="$area/a"; b="$area/b"; new_repository "$a"; new_repository "$b"
(cd "$a" && bash "$settings_script" set "$a" escapes .claude/mash-workbench/escapes --team >/dev/null)
(cd "$a" && bash "$settings_script" set "$a" backlog docs/backlog.md --team >/dev/null)
base=$(git -C "$a" rev-parse HEAD~1); head=$(git -C "$a" rev-parse HEAD)
# shellcheck disable=SC2016  # the inner bash expands its arguments
from() { local folder=$1; shift; run_capturing bash -c 'cd "$1" && shift && "$@"' _ "$folder" "$@"; }
from "$b" bash "$rr/skills/add-reviewer/escape-add.sh" "$a" src/x wrong-result one --body "text"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "not in the repository"
# shellcheck disable=SC2016  # the inner shell expands these
from "$b" bash -c 'printf -- "---\narea: src/x\nclass: wrong-result\nslug: two\n---\ntext\n" | bash "$1" --batch - "$2"' _ "$rr/skills/add-reviewer/escape-add.sh" "$a"
assert_eq "$captured_exit_code" "6"
from "$b" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title" "why"
assert_eq "$captured_exit_code" "6"
from "$b" bash "$rr/skills/review-changes/review-log.sh" add "$a" "$base" "$head"
assert_eq "$captured_exit_code" "6"
from "$area" bash "$rr/skills/add-reviewer/escape-add.sh" "$a" src/x wrong-result one --body "text"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$a/.claude/mash-workbench/escapes" && ! -e "$a/docs/backlog.md" && ! -e "$a/.claude/mash-workbench/reviews.log" ]] \
  || { echo "  a script wrote into another repository"; exit 1; }
# Reads stay free.
from "$b" bash "$rr/skills/add-reviewer/escape-add.sh" --list "$a" src/x
assert_eq "$captured_exit_code" "0"
# From the repository itself, a subfolder and a linked worktree, the writes work.
mkdir -p "$a/src"; git -C "$a" worktree add --quiet "$a/.claude/worktrees/w1" -b w1
for folder in "$a" "$a/src" "$a/.claude/worktrees/w1"; do
  from "$folder" bash "$rr/skills/add-reviewer/escape-add.sh" "$a" src/x wrong-result "from-$(basename "$folder")" --body "text"
  assert_eq "$captured_exit_code" "0"
done
from "$a/src" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title" "why"
assert_eq "$captured_exit_code" "0"
from "$a/.claude/worktrees/w1" bash "$rr/skills/review-changes/review-log.sh" add "$a" "$base" "$head"
assert_eq "$captured_exit_code" "0"
# Outside git, the backlog goes only to a folder that holds the current folder.
plain="$area/plain"; mkdir -p "$plain/sub"
from "$area" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "6"
from "$plain/sub" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "0"

# 2. reviews.log is this clone's own: a committed one is not read, and add refuses to append to it.
c="$area/c"; new_repository "$c"; mkdir -p "$c/.claude/mash-workbench"
cbase=$(git -C "$c" rev-parse HEAD~1); chead=$(git -C "$c" rev-parse HEAD)
printf '2026-01-01 %s %s - -\n' "$cbase" "$chead" > "$c/.claude/mash-workbench/reviews.log"
git -C "$c" add -f .claude/mash-workbench/reviews.log; git -C "$c" commit --quiet -m "chore: a log"
chead2=$(git -C "$c" rev-parse HEAD)
from "$c" bash "$rr/skills/review-changes/review-log.sh" reviewed "$c" "$chead"
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "not read"
from "$c" bash "$rr/skills/review-changes/review-log.sh" add "$c" "$chead" "$chead2"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git rm --cached"
# An untracked log without the exclude line that add writes is not read either.
d="$area/d"; new_repository "$d"; mkdir -p "$d/.claude/mash-workbench"
dbase=$(git -C "$d" rev-parse HEAD~1); dhead=$(git -C "$d" rev-parse HEAD)
printf '2026-01-01 %s %s - -\n' "$dbase" "$dhead" > "$d/.claude/mash-workbench/reviews.log"
from "$d" bash "$rr/skills/review-changes/review-log.sh" reviewed "$d" "$dhead"
assert_eq "$captured_exit_code" "1"
# The log that add writes answers.
from "$a" bash "$rr/skills/review-changes/review-log.sh" reviewed "$a" "$head"
assert_eq "$captured_exit_code" "0"

# 3. No control characters reach the output from files that others can commit.
escapes="$a/.claude/mash-workbench/escapes"
printf -- '---\ndate: 2026-01-02\narea: src/x\nclass: wrong-result\nsource: https://example.test/%s]0;x\a\n---\n\nhidden %s[2K text %s]8;;http://x\a\n' "$esc" "$esc" "$esc" > "$escapes/2026-01-02-planted.md"
from "$a" bash "$rr/skills/add-reviewer/escape-add.sh" --list "$a" src/x
no_escape_byte "$captured_output" "--list"
assert_contains "$captured_output" "hidden"
printf -- '---\ndate: 2026-01-03\narea: src/x\nclass: wrong%s[2K-result\n---\n\ntext\n' "$esc" > "$escapes/2026-01-03-planted.md"
from "$a" bash "$rr/skills/add-reviewer/escapes-report.sh" "$a"
no_escape_byte "$captured_output" "report"
assert_contains "$captured_output" "src/x"
printf -- '- [ ] 2020-01-01 · script · Planted %s[2K entry — why\n' "$esc" >> "$a/docs/backlog.md"
from "$a" bash "$mw/skills/scout/backlog-stale.sh" "$a" 1
no_escape_byte "$captured_output" "backlog-stale"
assert_contains "$captured_output" "Planted"
printf 'escapes.threshold=3%s[2K\n' "$esc" >> "$a/.claude/mash-workbench/settings"
from "$a" bash "$settings_script" get "$a" escapes.threshold
no_escape_byte "$captured_output" "get"
printf 'escapes=x%s[2K\n' "$esc" > "$a/.claude/mash-workbench/settings.extra"
from "$a" env "REVIEW_ROUTING_ESCAPES=x${esc}[2K" bash "$settings_script" path "$a" escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "control character"

# 4. A partial clone with a git older than 2.44: review-log.sh computes nothing (no fetch can start).
a_marker="$area/fetched"; payload="$area/payload.sh"
printf '#!/bin/sh\ntouch "%s"\n' "$a_marker" > "$payload"; chmod +x "$payload"
git -C "$a" config uploadpack.allowFilter true
git clone --quiet --no-local --filter=blob:none "file://$a" "$area/partial" 2>/dev/null
git -C "$area/partial" config remote.origin.uploadpack "$payload"
stub="$area/stub"; mkdir -p "$stub"
# shellcheck disable=SC2016  # the inner shell expands these
printf '#!/bin/sh\nif [ "$1" = --version ] || [ "$1" = version ]; then echo "git version 2.43.0"; exit 0; fi\nexec "%s" "$@"\n' "$(command -v git)" > "$stub/git"
chmod +x "$stub/git"
from "$area/partial" env PATH="$stub:$PATH" bash "$rr/skills/review-changes/review-log.sh" add "$area/partial" "$base" "$head"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "older than 2.44"
[[ ! -e "$a_marker" ]] || { echo "  a fetch started"; exit 1; }

# 6. Windows (Git Bash, MSYS, Cygwin): no allow rule is offered.
mkdir -p "$stub/win"; printf '#!/bin/sh\necho MINGW64_NT-10.0-19045\n' > "$stub/win/uname"; chmod +x "$stub/win/uname"
for rules in "$rr/skills/review-changes/permission-rules.sh" "$mw/skills/scout/permission-rules.sh"; do
  from "$a" env PATH="$stub/win:$PATH" bash "$rules" "$a"
  assert_not_contains "$captured_output" "add: "
  assert_contains "$captured_output" "not tested there"
done
echo "consumer safety: ok"
