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
printf -- '- [ ] 2020-01-01 · script · Planted %s[2K \302\233 entry — why\n' "$esc" >> "$a/docs/backlog.md"
from "$a" bash "$mw/skills/scout/backlog-stale.sh" "$a" 1
no_escape_byte "$captured_output" "backlog-stale"
assert_contains "$captured_output" "Planted"
printf 'escapes.threshold=3%s[2K\n' "$esc" >> "$a/.claude/mash-workbench/settings"
from "$a" bash "$settings_script" get "$a" escapes.threshold
no_escape_byte "$captured_output" "get"
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

# 5. Windows (Git Bash, MSYS, Cygwin): no allow rule is offered.
mkdir -p "$stub/win"; printf '#!/bin/sh\necho MINGW64_NT-10.0-19045\n' > "$stub/win/uname"; chmod +x "$stub/win/uname"
for rules in "$rr/skills/review-changes/permission-rules.sh" "$mw/skills/scout/permission-rules.sh"; do
  from "$a" env PATH="$stub/win:$PATH" bash "$rules" "$a"
  assert_not_contains "$captured_output" "add: "
  assert_contains "$captured_output" "not tested there"
done
# 6. More text from committed files: the near-duplicate note of backlog-add.sh, the messages escape-migrate.sh passes
#    on, and the file names of find-checks.sh carry no control character (C0, DEL, or C1 as UTF-8).
from "$a" bash "$mw/skills/scout/backlog-add.sh" "$a" script "Planted entry duplicate" "why"
assert_contains "$captured_output" "near duplicate"
no_escape_byte "$captured_output" "backlog-add near duplicate"
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (backlog-add)"; exit 1; }
e="$area/e"; new_repository "$e"; mkdir -p "$e/docs"
printf -- '- 2026-01-01 · src/a b%s[2K · wrong-result · https://x.test/1\n- 2026-01-02 · only two fields %s[2K \302\233\n' "$esc" "$esc" > "$e/docs/review-escapes.md"
from "$e" bash "$rr/skills/add-reviewer/escape-migrate.sh" "$e"
no_escape_byte "$captured_output" "escape-migrate"
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (escape-migrate)"; exit 1; }
mkdir -p "$e/.github/workflows"
c1=$'\302\233'
printf 'jobs:\n  t:\n    steps:\n      - run: npm test\n' > "$e/.github/workflows/x${esc}]0;T${esc}\\${c1}.yml"
from "$e" bash "$rr/skills/review-changes/find-checks.sh" "$e"
no_escape_byte "$captured_output" "find-checks"
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (find-checks)"; exit 1; }

# 7. Outside git means outside git: a <repo-root> that is not in git, above the session's repository, is refused.
top="$area/top"; mkdir -p "$top"; new_repository "$top/r"
from "$top/r" env MASH_WORKBENCH_BACKLOG=notes/backlog.md bash "$mw/skills/scout/backlog-add.sh" "$top" script "A title" "why"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$top/notes/backlog.md" ]] || { echo "  backlog-add wrote above the session's repository"; exit 1; }

# 8. review-log.sh add does not adopt a reviews.log that it did not start (one a patch created has no exclude line).
f="$area/f"; new_repository "$f"; mkdir -p "$f/.claude/mash-workbench"
fbase=$(git -C "$f" rev-parse HEAD~1); fhead=$(git -C "$f" rev-parse HEAD)
printf '2026-01-01 %s %s - -\n' "$fbase" "$fhead" > "$f/.claude/mash-workbench/reviews.log"
from "$f" bash "$rr/skills/review-changes/review-log.sh" add "$f" "$fbase" "$fhead"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "did not start"
from "$f" bash "$rr/skills/review-changes/review-log.sh" reviewed "$f" "$fhead"
assert_eq "$captured_exit_code" "1"

# 9. A record from a linked worktree of a bare repository succeeds without a "bare repository" message.
git clone --quiet --bare "$a" "$area/bare.git"; git -C "$area/bare.git" worktree add --quiet "$area/bare-linked" -b linked
from "$area/bare-linked" env REVIEW_ROUTING_ESCAPES="$area/bare-escapes" bash "$rr/skills/add-reviewer/escape-add.sh" "$area/bare-linked" src/x wrong-result bare-one --body "text"
assert_eq "$captured_exit_code" "0"
assert_not_contains "$captured_output" "bare repository"
# 10. The control-character refusal for paths does not depend on the locale: a C1 control (U+009B as UTF-8) in a
#     committed escapes path is refused under LC_ALL=C too, and nothing is recorded.
g="$area/g"; new_repository "$g"; mkdir -p "$g/.claude/mash-workbench"
printf 'escapes=docs/e\302\23331mRED\n' > "$g/.claude/mash-workbench/settings"
for locale in C POSIX; do
  from "$g" env LC_ALL="$locale" bash "$settings_script" path "$g" escapes
  assert_eq "$captured_exit_code" "6"
  from "$g" env LC_ALL="$locale" bash "$settings_script" check-escapes-path "$g" $'docs/e\302\23331m'
  assert_eq "$captured_exit_code" "6"
  from "$g" env LC_ALL="$locale" bash "$rr/skills/add-reviewer/escape-add.sh" "$g" src/x wrong-result c1 --body "text"
  assert_eq "$captured_exit_code" "6"
  [[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output ($locale)"; exit 1; }
done
[[ ! -e "$g/docs" ]] || { echo "  a C1 path was created"; exit 1; }

# 11. Outside git, a relative backlog path that climbs out of <repo-root> is refused before any folder is created.
from "$plain" env MASH_WORKBENCH_BACKLOG=../outside-x/x.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$area/outside-x" ]] || { echo "  backlog-add created a folder outside <repo-root>"; exit 1; }

# 12. The repo: line of an outside folder that is refused is printed without control characters.
own_dir="$area/owned"; mkdir -p "$own_dir"; printf '# Review escapes\nrepo: github.com/other/x%s[2K\n' "$esc" > "$own_dir/README.md"
from "$a" bash "$settings_script" check-escapes-path "$a" "$own_dir"
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "owner line"
# 13. A committed settings value with a backslash and an escape sequence: the refusal names no control character, in
#     the read commands too, also under LC_ALL=C with a C1 control. A line feed or a tab in a path is refused.
h="$area/h"; new_repository "$h"; mkdir -p "$h/.claude/mash-workbench"
printf 'escapes=docs/%s]0;owned\a%s[2K\\x\nbacklog=docs/%s[31mRED\\b.md\n' "$esc" "$esc" "$esc" > "$h/.claude/mash-workbench/settings"
for command in "$rr/skills/add-reviewer/escapes-report.sh $h" "$rr/skills/add-reviewer/escape-add.sh --list $h src/x" \
  "$rr/skills/add-reviewer/escape-add.sh $h src/x wrong-result bs --body text" "$mw/skills/scout/backlog-add.sh $h script T why"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  from "$h" bash $command
  no_escape_byte "$captured_output" "backslash refusal: $command"
done
printf 'escapes=docs/e\302\233x\\y\n' > "$h/.claude/mash-workbench/settings"
from "$h" env LC_ALL=C bash "$rr/skills/add-reviewer/escapes-report.sh" "$h"
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (backslash refusal)"; exit 1; }
from "$h" env REVIEW_ROUTING_ESCAPES=$'docs/a\nb' bash "$settings_script" path "$h" escapes
assert_eq "$captured_exit_code" "6"
from "$h" bash "$settings_script" check-escapes-path "$h" $'docs/a\tb'
assert_eq "$captured_exit_code" "6"

# 14. A committed folder whose name holds an escape sequence, shaped like a git directory: the refusal names it cleanly.
odd="$h/tools/x${esc}[2Ky"; mkdir -p "$odd/objects" "$odd/refs"; printf 'ref: refs/heads/main\n' > "$odd/HEAD"
from "$odd" bash "$rr/skills/add-reviewer/escape-add.sh" "$odd" src/x wrong-result odd --body "text"
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "anchor message"
# 15. A stale allow rule that holds an escape sequence is listed for removal without it.
mkdir -p "$a/.claude"
printf '{"permissions": {"allow": ["Bash(bash /old/review-routing/0.0.1/skills/add-reviewer/escape-add.sh%s[2K%s *)"]}}\n' "$esc" "$c1" > "$a/.claude/settings.local.json"
from "$a" bash "$rr/skills/review-changes/permission-rules.sh" "$a"
assert_contains "$captured_output" "remove: "
no_escape_byte "$captured_output" "permission-rules remove line"
[[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (permission-rules)"; exit 1; }
rm "$a/.claude/settings.local.json"
# 16. A repository whose own folder name holds an escape sequence (a submodule path can hold one): every writing script
#     and permission-rules.sh refuse it before they print a path, and no escape byte reaches the output.
oddrepo="$area/vendor/x${esc}]0;PWNED${c1}y"; mkdir -p "$(dirname "$oddrepo")"; new_repository "$oddrepo"
for command in "$rr/skills/add-reviewer/escape-add.sh $oddrepo src/x wrong-result odd --body text" \
  "$mw/skills/scout/backlog-add.sh $oddrepo script T why" "$rr/skills/review-changes/permission-rules.sh $oddrepo" \
  "$rr/skills/review-changes/review-log.sh reviewed $oddrepo HEAD"; do
  # shellcheck disable=SC2086  # the words are split on purpose (no word holds a space)
  from "$oddrepo" bash $command
  assert_eq "$captured_exit_code" "6"
  no_escape_byte "$captured_output" "repository path: $command"
  [[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (repository path)"; exit 1; }
done
# A linked worktree of a bare repository (no main worktree) in such a folder is refused too.
git -C "$area/bare.git" worktree add --quiet "$area/wt${esc}[2Kx" -b oddwt
from "$area/wt${esc}[2Kx" env REVIEW_ROUTING_ESCAPES="$area/bare-escapes" bash "$rr/skills/add-reviewer/escape-add.sh" "$area/wt${esc}[2Kx" src/x wrong-result oddwt --body "text"
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "bare worktree path"
# Outside git, a <repo-root> whose own name holds one is refused before a message can name it.
plain_odd="$area/plain${esc}[2Kodd"; mkdir -p "$plain_odd"
from "$plain_odd" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain_odd" script "A title" "why"
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "non-git root name"
# The current folder (inside a clean repository) holds one, and <repo-root> is outside git: the refusal is clean.
mkdir -p "$top/r/src/q${esc}[2Kz"
from "$top/r/src/q${esc}[2Kz" env MASH_WORKBENCH_BACKLOG=notes/backlog.md bash "$mw/skills/scout/backlog-add.sh" "$top" script "A title" "why"
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "backlog-add current folder"
# 17. Outside git, a <repo-root> with a line feed in its name is refused (a name must not add a line to the output).
lf_root="$area/lf"$'\n'"backlog-add: fake line"; mkdir -p "$lf_root"
from "$area" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$lf_root" script "A title" "why"
assert_eq "$captured_exit_code" "6"
assert_not_contains "$captured_output" "fake line"

# 18. git refuses the repository (here: an unknown repository format) and <repo-root> is a subfolder with an escape
#     sequence in its name: escape-add.sh and escape-migrate.sh name it without control characters.
k="$area/k"; new_repository "$k"; mkdir -p "$k/src/x${esc}]0;PWNED${c1}y"
git config --file "$k/.git/config" core.repositoryformatversion 99
for script in "$rr/skills/add-reviewer/escape-add.sh" "$rr/skills/add-reviewer/escape-migrate.sh"; do
  if [[ "$script" == *escape-add.sh ]]; then
    from "$k" bash "$script" "$k/src/x${esc}]0;PWNED${c1}y" src/x wrong-result k --body "text"
  else
    from "$k" bash "$script" "$k/src/x${esc}]0;PWNED${c1}y"
  fi
  [[ "$captured_exit_code" != 0 ]] || { echo "  $script accepted a repository git refuses"; exit 1; }
  no_escape_byte "$captured_output" "git refused: $script"
  [[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (git refused)"; exit 1; }
done
git config --file "$k/.git/config" core.repositoryformatversion 0
echo "consumer safety: ok"
