# shellcheck shell=bash
# What an allow rule pre-approves must stay safe on the user's machine: a write goes only to the repository the session
# works in; text from files that others can commit reaches the terminal without control characters; no allow rules
# where the checks are untested (Windows).
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
mw="$PWD/plugins/mash-workbench"
settings_script="$mw/scripts/mash-settings.sh"
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
# shellcheck disable=SC2016  # the inner bash expands its arguments
from() { local folder=$1; shift; run_capturing bash -c 'cd "$1" && shift && "$@"' _ "$folder" "$@"; }
from "$b" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "not in the repository"
from "$area" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title" "why"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$a/docs/backlog.md" ]] || { echo "  a script wrote into another repository"; exit 1; }
# From the repository itself, a subfolder and a linked worktree, the writes work.
mkdir -p "$a/src"; git -C "$a" worktree add --quiet "$a/.claude/worktrees/w1" -b w1
for folder in "$a" "$a/src" "$a/.claude/worktrees/w1"; do
  from "$folder" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title from $(basename "$folder")" "why"
  assert_eq "$captured_exit_code" "0"
done
from "$a/src" bash "$mw/skills/scout/backlog-add.sh" "$a" script "A title" "why"
assert_eq "$captured_exit_code" "0"
# Outside git, the backlog goes only to a folder that holds the current folder.
plain="$area/plain"; mkdir -p "$plain/sub"
from "$area" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "6"
from "$plain/sub" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "0"

# 3. No control characters reach the output from files that others can commit.
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

# 5. Windows (Git Bash, MSYS, Cygwin): no allow rule is offered.
stub="$area/stub"; mkdir -p "$stub/win"; printf '#!/bin/sh\necho MINGW64_NT-10.0-19045\n' > "$stub/win/uname"; chmod +x "$stub/win/uname"
from "$a" env PATH="$stub/win:$PATH" bash "$mw/skills/scout/permission-rules.sh" "$a"
assert_not_contains "$captured_output" "add: "
assert_contains "$captured_output" "not tested there"
# 6. More text from committed files: the near-duplicate note of backlog-add.sh carries no control character (C0, DEL,
#    or C1 as UTF-8).
from "$a" bash "$mw/skills/scout/backlog-add.sh" "$a" script "Planted entry duplicate" "why"
assert_contains "$captured_output" "near duplicate"
no_escape_byte "$captured_output" "backlog-add near duplicate"
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (backlog-add)"; exit 1; }
c1=$'\302\233'

# 7. Outside git means outside git: a <repo-root> that is not in git, above the session's repository, is refused.
top="$area/top"; mkdir -p "$top"; new_repository "$top/r"
from "$top/r" env MASH_WORKBENCH_BACKLOG=notes/backlog.md bash "$mw/skills/scout/backlog-add.sh" "$top" script "A title" "why"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$top/notes/backlog.md" ]] || { echo "  backlog-add wrote above the session's repository"; exit 1; }

# 9. A bare repository with a linked worktree (used by case 16).
git clone --quiet --bare "$a" "$area/bare.git"; git -C "$area/bare.git" worktree add --quiet "$area/bare-linked" -b linked
# 10. The control-character refusal for paths does not depend on the locale: a C1 control (U+009B as UTF-8) in a
#     committed escapes or backlog path is refused under LC_ALL=C too.
g="$area/g"; new_repository "$g"; mkdir -p "$g/.claude/mash-workbench"
printf 'escapes=docs/e\302\23331mRED\nbacklog=docs/e\302\23331mRED.md\n' > "$g/.claude/mash-workbench/settings"
for locale in C POSIX; do
  from "$g" env LC_ALL="$locale" bash "$settings_script" path "$g" escapes
  assert_eq "$captured_exit_code" "6"
  from "$g" env LC_ALL="$locale" bash "$settings_script" check-escapes-path "$g" $'docs/e\302\23331m'
  assert_eq "$captured_exit_code" "6"
  [[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output ($locale)"; exit 1; }
  from "$g" env LC_ALL="$locale" bash "$mw/skills/scout/backlog-add.sh" "$g" script T why
  assert_eq "$captured_exit_code" "6"
  [[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (backlog-add, $locale)"; exit 1; }
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
from "$h" bash "$mw/skills/scout/backlog-add.sh" "$h" script T why
no_escape_byte "$captured_output" "backslash refusal: backlog-add"
printf 'backlog=docs/e\302\233x\\y\n' > "$h/.claude/mash-workbench/settings"
from "$h" env LC_ALL=C bash "$mw/skills/scout/backlog-add.sh" "$h" script T why
[[ "$captured_output" != *$'\302\233'* ]] || { echo "  a C1 control reached the output (backslash refusal)"; exit 1; }
from "$h" env REVIEW_ROUTING_ESCAPES=$'docs/a\nb' bash "$settings_script" path "$h" escapes
assert_eq "$captured_exit_code" "6"
from "$h" bash "$settings_script" check-escapes-path "$h" $'docs/a\tb'
assert_eq "$captured_exit_code" "6"

# 14. A committed folder whose name holds an escape sequence, shaped like a git directory: the refusal names it cleanly.
odd="$h/tools/x${esc}[2Ky"; mkdir -p "$odd/objects" "$odd/refs"; printf 'ref: refs/heads/main\n' > "$odd/HEAD"
from "$odd" bash "$mw/skills/scout/backlog-add.sh" "$odd" script T why
assert_eq "$captured_exit_code" "6"
no_escape_byte "$captured_output" "anchor message"
# 15. A stale allow rule that holds an escape sequence is listed for removal without it.
mkdir -p "$a/.claude"
printf '{"permissions": {"allow": ["Bash(bash /old/mash-workbench/0.0.1/skills/scout/backlog-add.sh%s[2K%s *)"]}}\n' "$esc" "$c1" > "$a/.claude/settings.local.json"
from "$a" bash "$mw/skills/scout/permission-rules.sh" "$a"
assert_contains "$captured_output" "remove: "
no_escape_byte "$captured_output" "permission-rules remove line"
[[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (permission-rules)"; exit 1; }
rm "$a/.claude/settings.local.json"
# 16. A repository whose own folder name holds an escape sequence (a submodule path can hold one): the writing script
#     and permission-rules.sh refuse it before they print a path, and no escape byte reaches the output.
oddrepo="$area/vendor/x${esc}]0;PWNED${c1}y"; mkdir -p "$(dirname "$oddrepo")"; new_repository "$oddrepo"
for command in "$mw/skills/scout/backlog-add.sh $oddrepo script T why" "$mw/skills/scout/permission-rules.sh $oddrepo"; do
  # shellcheck disable=SC2086  # the words are split on purpose (no word holds a space)
  from "$oddrepo" bash $command
  assert_eq "$captured_exit_code" "6"
  no_escape_byte "$captured_output" "repository path: $command"
  [[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (repository path)"; exit 1; }
done
# A linked worktree of a bare repository (no main worktree) in such a folder is refused too.
git -C "$area/bare.git" worktree add --quiet "$area/wt${esc}[2Kx" -b oddwt
from "$area/wt${esc}[2Kx" bash "$mw/skills/scout/backlog-add.sh" "$area/wt${esc}[2Kx" script T why
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
#     sequence in its name: backlog-add.sh names it without control characters.
k="$area/k"; new_repository "$k"; mkdir -p "$k/src/x${esc}]0;PWNED${c1}y"
git config --file "$k/.git/config" core.repositoryformatversion 99
from "$k" bash "$mw/skills/scout/backlog-add.sh" "$k/src/x${esc}]0;PWNED${c1}y" script T why
[[ "$captured_exit_code" != 0 ]] || { echo "  backlog-add.sh accepted a repository git refuses"; exit 1; }
no_escape_byte "$captured_output" "git refused: backlog-add"
[[ "$captured_output" != *"$c1"* ]] || { echo "  a C1 control reached the output (git refused)"; exit 1; }
# (No restore: the EXIT trap deletes $area.)

# 19. A line feed in a folder name never adds a line of its own to a message: the repository's own path, a <repo-root>
#     outside git for backlog-add.sh, and a current folder inside a clean repository.
fake_line() { if printf '%s\n' "$1" | grep -q '^FAKE'; then echo "  a folder name added a line ($2)"; exit 1; fi; }
lfrepo="$area/lfr"$'\n'"FAKE repo"; new_repository "$lfrepo"
from "$area" bash "$settings_script" main-worktree "$lfrepo"
assert_eq "$captured_exit_code" "6"
fake_line "$captured_output" "mash-settings refusal"
lfplain="$area/lfp"$'\n'"FAKE plain"; mkdir -p "$lfplain"
from "$area" bash "$mw/skills/scout/backlog-add.sh" "$lfplain" script T why
fake_line "$captured_output" "backlog-add not in git"
lfsub="$top/r/src/lf"$'\n'"FAKE sub"; mkdir -p "$lfsub"
from "$lfsub" env MASH_WORKBENCH_BACKLOG=notes/backlog.md bash "$mw/skills/scout/backlog-add.sh" "$top" script "A title" "why"
assert_eq "$captured_exit_code" "6"
fake_line "$captured_output" "backlog-add current folder"
lfcur="$area/cur"$'\n'"FAKE cur"; mkdir -p "$lfcur"
from "$lfcur" env MASH_WORKBENCH_BACKLOG=notes.md bash "$mw/skills/scout/backlog-add.sh" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "6"
fake_line "$captured_output" "backlog-add current folder outside root"
from "$lfsub" bash "$mw/skills/scout/backlog-add.sh" "$a" script T why
fake_line "$captured_output" "same-repository message"
echo "consumer safety: ok"
