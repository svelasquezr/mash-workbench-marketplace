# shellcheck shell=bash
# mash-settings.sh: one settings lookup and one escapes-path check for every worktree of a repository.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
settings_script="$PWD/plugins/review-routing/scripts/mash-settings.sh"
path_script="$PWD/plugins/review-routing/skills/add-reviewer/escapes-path.sh"
# The path checks refuse /tmp, so the whole fixture lives under $HOME (never under /tmp).
area=$(mktemp -d "$HOME/.mash-settings-test.XXXXXX"); trap 'rm -rf "$area"' EXIT
case "$(cd "$area" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$area"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES MASH_WORKBENCH_BACKLOG
normalized() { (cd "$1" && pwd -P); }
settings() { bash "$settings_script" "$@"; }
new_repository() { git init --quiet "$1"; git -C "$1" commit --quiet --allow-empty -m "chore: base"; }

# 1. Same answer from the main worktree and from a linked worktree under .claude/worktrees/.
repo="$area/repo"; new_repository "$repo"
printf '.claude/worktrees/\n' >> "$repo/.git/info/exclude"
git -C "$repo" worktree add --quiet .claude/worktrees/w1 -b w1
w1="$repo/.claude/worktrees/w1"
main=$(normalized "$repo")
assert_eq "$(settings main-worktree "$repo")" "$main"
assert_eq "$(settings main-worktree "$w1")" "$main"
mkdir -p "$repo/src"
assert_eq "$(settings main-worktree "$repo/src")" "$main"
assert_eq "$(settings home "$w1")" "$main/.claude/mash-workbench"
[[ ! -e "$repo/.claude/mash-workbench" ]] || { echo "  home created the folder"; exit 1; }
settings set "$w1" escapes shared --local >/dev/null
assert_file "$repo/.claude/mash-workbench/settings.local"
[[ ! -e "$w1/.claude/mash-workbench" ]] || { echo "  set wrote into the linked worktree"; exit 1; }
assert_eq "$(settings get "$repo" escapes)" "shared"
assert_eq "$(settings get "$w1" escapes)" "shared"
# The private file is excluded: neither worktree shows a change.
assert_eq "$(git -C "$repo" status --porcelain)" ""
assert_eq "$(git -C "$w1" status --porcelain)" ""

# 2. Precedence: environment variable, then settings.local, then settings.
prec="$area/prec"; new_repository "$prec"; mkdir -p "$prec/.claude/mash-workbench"
printf 'escapes=a\n' > "$prec/.claude/mash-workbench/settings"
printf 'escapes=b\n' > "$prec/.claude/mash-workbench/settings.local"
assert_eq "$(REVIEW_ROUTING_ESCAPES=c settings get "$prec" escapes)" "c"
assert_eq "$(settings get "$prec" escapes)" "b"
# An empty variable counts as unset.
assert_eq "$(REVIEW_ROUTING_ESCAPES='' settings get "$prec" escapes)" "b"
rm "$prec/.claude/mash-workbench/settings.local"
assert_eq "$(settings get "$prec" escapes)" "a"
rm "$prec/.claude/mash-workbench/settings"
run_capturing settings get "$prec" escapes
assert_eq "$captured_exit_code" "3"
# backlog maps to MASH_WORKBENCH_BACKLOG; other keys have no variable.
assert_eq "$(MASH_WORKBENCH_BACKLOG=b.md settings get "$prec" backlog)" "b.md"
run_capturing env REVIEW_ROUTING_ESCAPES=x bash "$settings_script" get "$prec" escapes.threshold
assert_eq "$captured_exit_code" "3"

# 3. File parsing: CRLF, comments, empty lines, the first = splits, the last duplicate wins.
printf 'x=1\r\n# escapes=no\r\n\r\nkey=va=lue\r\ndup=1\ndup=2\n' > "$prec/.claude/mash-workbench/settings"
assert_eq "$(settings get "$prec" x)" "1"
assert_eq "$(settings get "$prec" key)" "va=lue"
assert_eq "$(settings get "$prec" dup)" "2"
run_capturing settings get "$prec" escapes
assert_eq "$captured_exit_code" "3"

# 4. set --local twice: one line, one exclude line; --team keeps other lines and touches no exclude file.
settings set "$prec" escapes first --local >/dev/null
settings set "$prec" escapes second --local >/dev/null
assert_eq "$(grep -c '^escapes=' "$prec/.claude/mash-workbench/settings.local")" "1"
assert_eq "$(settings get "$prec" escapes)" "second"
assert_eq "$(grep -cx '.claude/mash-workbench/settings.local' "$prec/.git/info/exclude")" "1"
settings set "$prec" dup 3 --team >/dev/null
assert_eq "$(grep -c '^dup=' "$prec/.claude/mash-workbench/settings")" "1"
assert_eq "$(settings get "$prec" dup)" "3"
assert_eq "$(settings get "$prec" key)" "va=lue"
assert_contains "$(cat "$prec/.claude/mash-workbench/settings")" "# escapes=no"
assert_eq "$(grep -c 'settings.local' "$prec/.git/info/exclude")" "1"
# An exclude file without a final newline gets the line on its own row.
excl="$area/excl"; new_repository "$excl"; printf 'keep-me' > "$excl/.git/info/exclude"
settings set "$excl" a b --local >/dev/null
assert_eq "$(grep -cx 'keep-me' "$excl/.git/info/exclude")" "1"
assert_eq "$(grep -cx '.claude/mash-workbench/settings.local' "$excl/.git/info/exclude")" "1"
# set keeps a replaced file's mode, and a new file gets the umask mode, not mktemp's 0600.
# shellcheck disable=SC2012  # ls -l is the portable way to read a mode (stat flags differ between GNU and BSD)
mode() { ls -l "$1" | cut -c1-10; }
chmod 644 "$prec/.claude/mash-workbench/settings"
settings set "$prec" dup 4 --team >/dev/null
assert_eq "$(mode "$prec/.claude/mash-workbench/settings")" "-rw-r--r--"
chmod 640 "$prec/.claude/mash-workbench/settings"
settings set "$prec" dup 3 --team >/dev/null
assert_eq "$(mode "$prec/.claude/mash-workbench/settings")" "-rw-r-----"
modes="$area/modes"; new_repository "$modes"
(umask 022 && bash "$settings_script" set "$modes" k v --team >/dev/null)
assert_eq "$(mode "$modes/.claude/mash-workbench/settings")" "-rw-r--r--"
assert_eq "$(find "$prec/.claude/mash-workbench" "$modes/.claude/mash-workbench" -name '.settings*' | wc -l | tr -d ' ')" "0"

# Finding 8: a held lock makes set fail after a short wait, with the exclude line already in place; no lock is left.
locked="$area/locked"; new_repository "$locked"; mkdir -p "$locked/.claude/mash-workbench/.settings.lock"
run_capturing settings set "$locked" k v --local
assert_eq "$captured_exit_code" "1"
assert_contains "$captured_output" "another mash-settings.sh is writing"
[[ ! -e "$locked/.claude/mash-workbench/settings.local" ]] || { echo "  wrote while the lock was held"; exit 1; }
assert_eq "$(grep -cx '.claude/mash-workbench/settings.local' "$locked/.git/info/exclude")" "1"
rmdir "$locked/.claude/mash-workbench/.settings.lock"
settings set "$locked" k v --local >/dev/null
assert_eq "$(settings get "$locked" k)" "v"
[[ ! -e "$locked/.claude/mash-workbench/.settings.lock" ]] || { echo "  set left its lock"; exit 1; }

# unset removes every line of the key from one file, compares keys whole, keeps the other lines, and takes the lock.
unset_repo="$area/unset"; new_repository "$unset_repo"
printf '# keep\ndeclined.src/b=2026-11-01:3\ndeclined.src/bx=1\ndeclined.src/b=2026-11-02:4\r\nother=1\n' > "$area/unset-settings"
mkdir -p "$unset_repo/.claude/mash-workbench"; cp "$area/unset-settings" "$unset_repo/.claude/mash-workbench/settings.local"
run_capturing settings unset "$unset_repo" declined.src/b --local
assert_eq "$captured_exit_code" "0"
assert_eq "$(cat "$unset_repo/.claude/mash-workbench/settings.local")" "$(printf '# keep\ndeclined.src/bx=1\nother=1')"
run_capturing settings get "$unset_repo" declined.src/b
assert_eq "$captured_exit_code" "3"
# A key that is not there, or a file that does not exist, is not an error, and nothing is created.
run_capturing settings unset "$unset_repo" declined.src/b --local
assert_eq "$captured_exit_code" "0"
run_capturing settings unset "$unset_repo" anything --team
assert_eq "$captured_exit_code" "0"
[[ ! -e "$unset_repo/.claude/mash-workbench/settings" ]] || { echo "  unset created the team file"; exit 1; }
mkdir "$unset_repo/.claude/mash-workbench/.settings.lock"
run_capturing settings unset "$unset_repo" other --local
assert_eq "$captured_exit_code" "1"
assert_eq "$(settings get "$unset_repo" other)" "1"
rmdir "$unset_repo/.claude/mash-workbench/.settings.lock"
for bad in "unset $unset_repo k" "unset $unset_repo k --both"; do
  # shellcheck disable=SC2086  # split on purpose
  run_capturing bash "$settings_script" $bad
  assert_eq "$captured_exit_code" "2"
done

# 11. Keys with / and . are compared whole, never as patterns.
settings set "$prec" declined.src/billing 2026-11-21:3 --local >/dev/null
settings set "$prec" a.b 1 --local >/dev/null
settings set "$prec" axb 2 --local >/dev/null
assert_eq "$(settings get "$prec" declined.src/billing)" "2026-11-21:3"
assert_eq "$(settings get "$prec" a.b)" "1"
assert_eq "$(settings get "$prec" axb)" "2"
settings set "$prec" a.b 9 --local >/dev/null
assert_eq "$(settings get "$prec" axb)" "2"
assert_eq "$(settings get "$prec" a.b)" "9"
# A value with a backslash is kept as typed.
settings set "$prec" back 'a\nb' --local >/dev/null
assert_eq "$(settings get "$prec" back)" 'a\nb'

# Usage errors.
for bad in "frobnicate $prec" "get $prec" "set $prec k v" "set $prec k v --both" "main-worktree"; do
  # shellcheck disable=SC2086  # split on purpose: each entry is a list of arguments
  run_capturing bash "$settings_script" $bad
  assert_eq "$captured_exit_code" "2"
done
for bad_key in "a=b" "#c" ""; do
  run_capturing settings set "$prec" "$bad_key" v --local
  assert_eq "$captured_exit_code" "2"
done
run_capturing settings set "$prec" k $'two\nlines' --local
assert_eq "$captured_exit_code" "2"
not_repo=$(mktemp -d "$area/not-repo.XXXXXX")
run_capturing settings main-worktree "$not_repo"
assert_eq "$captured_exit_code" "2"
run_capturing settings main-worktree "$area/missing"
assert_eq "$captured_exit_code" "2"

# 5. Submodule: the main worktree is the submodule's folder; the exclude file is in the super repository's modules.
new_repository "$area/sub-source"
super="$area/super"; new_repository "$super"
git -C "$super" -c protocol.file.allow=always submodule --quiet add "$area/sub-source" sub
assert_eq "$(settings main-worktree "$super/sub")" "$(normalized "$super/sub")"
settings set "$super/sub" escapes e --local >/dev/null
assert_file "$super/sub/.claude/mash-workbench/settings.local"
assert_eq "$(grep -cx '.claude/mash-workbench/settings.local' "$super/.git/modules/sub/info/exclude")" "1"

# 6. Separate git dir: the work folder is the main worktree; from its linked worktree it cannot be found (exit 5).
git init --quiet --separate-git-dir="$area/sep.git" "$area/sepwork"
git -C "$area/sepwork" commit --quiet --allow-empty -m "chore: base"
assert_eq "$(settings main-worktree "$area/sepwork")" "$(normalized "$area/sepwork")"
mkdir -p "$area/sepwork/src"
assert_eq "$(settings main-worktree "$area/sepwork/src")" "$(normalized "$area/sepwork")"
git -C "$area/sepwork" worktree add --quiet "$area/sepwork-linked" -b linked
run_capturing settings main-worktree "$area/sepwork-linked"
assert_eq "$captured_exit_code" "5"
assert_contains "$captured_output" "main worktree not found"
# Finding 12: from that linked worktree an absolute path cannot be placed inside or outside the repo.
run_capturing bash "$settings_script" check-escapes-path "$area/sepwork-linked" "$area/sepwork/escapes"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "main worktree unknown: cannot tell if this path is inside the repo"
# Finding 13: set --local writes the exclude line into the separate git dir.
settings set "$area/sepwork" escapes e --local >/dev/null
assert_eq "$(grep -cx '.claude/mash-workbench/settings.local' "$area/sep.git/info/exclude")" "1"
assert_file "$area/sepwork/.claude/mash-workbench/settings.local"

# 7. Bare repository with a worktree: exit 5 from both; an environment value still answers get.
git clone --quiet --bare "$repo" "$area/bare.git"
git -C "$area/bare.git" worktree add --quiet "$area/bare-linked" -b linked
for folder in "$area/bare.git" "$area/bare-linked"; do
  run_capturing settings main-worktree "$folder"
  assert_eq "$captured_exit_code" "5"
  assert_contains "$captured_output" "bare repository"
  run_capturing settings get "$folder" escapes
  assert_eq "$captured_exit_code" "5"
done
assert_eq "$(REVIEW_ROUTING_ESCAPES=/abs/escapes settings get "$area/bare-linked" escapes)" "/abs/escapes"
# Finding 3: escapes-path.sh there needs an absolute path.
run_capturing env REVIEW_ROUTING_ESCAPES=notes/escapes bash "$path_script" "$area/bare-linked"
assert_eq "$captured_exit_code" "5"
assert_contains "$captured_output" "absolute path"
assert_eq "$(REVIEW_ROUTING_ESCAPES="$area/bare-escapes" bash "$path_script" "$area/bare-linked")" "$area/bare-escapes"
run_capturing bash "$path_script" "$area/bare-linked"
assert_eq "$captured_exit_code" "5"

# 8. Repo key: every clone spelling gives one key; no origin gives local/<main worktree folder name>.
keyed="$area/Keyed"; new_repository "$keyed"
git -C "$keyed" worktree add --quiet "$keyed/.claude/worktrees/k" -b k
assert_eq "$(settings repo-key "$keyed")" "local/keyed"
assert_eq "$(settings repo-key "$keyed/.claude/worktrees/k")" "local/keyed"
# Finding 1: a local-only repository accepts its own owner marker, whatever the case of its folder name.
mkdir -p "$area/keyed-escapes"; printf '# Review escapes\nrepo: local/keyed\n' > "$area/keyed-escapes/README.md"
run_capturing bash "$settings_script" check-escapes-path "$keyed" "$area/keyed-escapes"
assert_eq "$captured_exit_code" "0"
git -C "$keyed" remote add origin x
for url in 'git@github.com:Acme/Shop.git' 'ssh://git@github.com/acme/shop' 'https://user:token@github.com/acme/shop.git/' 'ssh://git@github.com:22/acme/shop.git'; do
  git -C "$keyed" remote set-url origin "$url"
  assert_eq "$(settings repo-key "$keyed")" "github.com/acme/shop"
done
# Finding 7: an scp-like path from the root gives the same key as the ssh:// spelling.
for url in 'git@example.org:/srv/shop.git' 'ssh://git@example.org/srv/shop.git'; do
  git -C "$keyed" remote set-url origin "$url"
  assert_eq "$(settings repo-key "$keyed")" "example.org/srv/shop"
done

# 9. check-escapes-path: every rule.
git -C "$repo" remote add origin https://github.com/Acme/Shop.git
check() { run_capturing bash "$settings_script" check-escapes-path "$@"; }
# A linked worktree is refused, spelled any way, also through .. segments.
for path in .claude/worktrees/w1/escapes "$w1/escapes" "$w1" .claude/x/../worktrees/w1/e; do
  check "$repo" "$path"
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "a linked worktree is deleted with its branch"
done
# Temporary folders are refused.
check "$repo" /tmp/mash-settings-check/escapes
assert_eq "$captured_exit_code" "6"
mkdir -p "$area/tmpdir"
run_capturing env TMPDIR="$area/tmpdir/" bash "$settings_script" check-escapes-path "$repo" "$area/tmpdir/escapes"
assert_eq "$captured_exit_code" "6"
# Finding 4: the scratchpad pattern applies only under a temporary root; a clone named claude-3 is fine.
check "$repo" "$area/code/claude-3/escapes"
assert_eq "$captured_exit_code" "0"
run_capturing env TMPDIR="$area/tmpdir" bash "$settings_script" check-escapes-path "$repo" "$area/tmpdir/claude-1000/project/escapes"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "scratchpad"
# Finding 5: a temporary root that resolves to / does not refuse every path.
run_capturing env TMPDIR=/ bash "$settings_script" check-escapes-path "$repo" "$area/outside/escapes"
assert_eq "$captured_exit_code" "0"
# Finding 6: the git directory is refused.
check "$repo" .git/escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "inside the git directory: cannot be committed or shared"
# Inside the repo: a relative path is from the main worktree, also when asked from a linked worktree.
for folder in "$repo" "$w1"; do
  check "$folder" .claude/mash-workbench/escapes
  assert_eq "$captured_exit_code" "0"
  assert_eq "$captured_output" "inside the repo: commit it to share with the team"
done
printf 'private-escapes/\n' >> "$repo/.git/info/exclude"
check "$w1" private-escapes
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "inside the repo, ignored: private to this clone"
# A tracked folder under an ignore pattern is still shared.
mkdir -p "$repo/kept"; printf 'x\n' > "$repo/kept/a.md"; git -C "$repo" add kept/a.md; git -C "$repo" commit --quiet -m "chore: kept"
printf 'kept/\n' >> "$repo/.git/info/exclude"
check "$repo" kept
assert_eq "$captured_output" "inside the repo: commit it to share with the team"
# Outside the repo, under $HOME.
check "$repo" "$area/outside/escapes"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "outside the repo: survives deleting the clone"
# Anything else.
check "$repo" "/mash-settings-nowhere-$$/escapes"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "outside the repo"
# Owner marker: outside the repo, another repo's folder is refused and this repo's (any case) is accepted.
mkdir -p "$area/other-owner" "$area/same-owner"
printf '# Review escapes\nrepo: github.com/other/thing\n' > "$area/other-owner/README.md"
printf '# Review escapes\r\nrepo: GitHub.com/Acme/Shop\r\n' > "$area/same-owner/README.md"
check "$repo" "$area/other-owner"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "owned by github.com/other/thing"
check "$repo" "$area/same-owner"
assert_eq "$captured_exit_code" "0"
# Inside the main worktree the folder is this repo's by construction: the marker is not checked.
mkdir -p "$repo/.claude/mash-workbench/escapes"
printf '# Review escapes\nrepo: git@github.com:acme/shop.git\n' > "$repo/.claude/mash-workbench/escapes/README.md"
check "$w1" .claude/mash-workbench/escapes
assert_eq "$captured_exit_code" "0"
# A bare repository has no main worktree: a relative path cannot be resolved; an absolute one is checked.
check "$area/bare-linked" escapes
assert_eq "$captured_exit_code" "5"
check "$area/bare-linked" "$area/bare-escapes"
assert_eq "$captured_exit_code" "0"
check "$area/bare-linked" "$area/bare-linked/escapes"
assert_eq "$captured_exit_code" "6"

# 10. escapes-path.sh from a linked worktree, with the setting in the main worktree's settings.local.
paths="$area/paths"; new_repository "$paths"
git -C "$paths" worktree add --quiet "$paths/.claude/worktrees/w" -b w
linked="$paths/.claude/worktrees/w"; paths_main=$(normalized "$paths")
run_capturing bash "$path_script" "$linked"
assert_eq "$captured_exit_code" "3"
assert_eq "$captured_output" ""
settings set "$paths" escapes off --local >/dev/null
run_capturing bash "$path_script" "$linked"
assert_eq "$captured_exit_code" "4"
assert_eq "$captured_output" ""
settings set "$paths" escapes .claude/mash-workbench/escapes --local >/dev/null
assert_eq "$(bash "$path_script" "$linked")" "$paths_main/.claude/mash-workbench/escapes"
settings set "$paths" escapes "$area/elsewhere" --local >/dev/null
assert_eq "$(bash "$path_script" "$linked")" "$area/elsewhere"
assert_eq "$(REVIEW_ROUTING_ESCAPES=notes/e.md bash "$path_script" "$linked")" "$paths_main/notes/e.md"
rm "$paths/.claude/mash-workbench/settings.local"
for old in docs/review-escapes.md docs/mash/review-escapes.md; do
  mkdir -p "$paths/$(dirname "$old")"; printf '# Review escapes\n' > "$paths/$old"
  assert_eq "$(bash "$path_script" "$linked" 2>/dev/null)" "$paths_main/$old"
  # shellcheck disable=SC2016  # the single quotes are meant: $1 and $2 expand in the inner bash
  run_capturing bash -c 'bash "$1" "$2" 2>&1 >/dev/null' _ "$path_script" "$linked"
  assert_contains "$captured_output" "old ledger format in use: $old; run escape-migrate.sh"
done

# Finding 2: escape-add.sh from a linked worktree writes into the main worktree's escapes folder, where a plain record
# and the report find it again.
add_script="$PWD/plugins/review-routing/skills/add-reviewer/escape-add.sh"
report_script="$PWD/plugins/review-routing/skills/add-reviewer/escapes-report.sh"
printf 'When X, Y happens.\n' > "$area/body.md"
led="$area/led"; new_repository "$led"
git -C "$led" worktree add --quiet "$led/.claude/worktrees/w" -b w
led_linked="$led/.claude/worktrees/w"
settings set "$led" escapes .claude/mash-workbench/escapes --local >/dev/null
bash "$add_script" "$led_linked" src/a wrong-result one --body-file "$area/body.md" >/dev/null
run_capturing bash "$add_script" "$led_linked" src/a missing-test two --body-file "$area/body.md"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded: .claude/mash-workbench/escapes/"
assert_eq "$(find "$led/.claude/mash-workbench/escapes" -name '*.md' ! -name README.md | wc -l | tr -d ' ')" "2"
[[ ! -e "$led_linked/.claude/mash-workbench" ]] || { echo "  recorded into the linked worktree"; exit 1; }
assert_contains "$(bash "$report_script" "$led_linked" 2>/dev/null)" "src/a: 2 escapes"

# Finding 11: escapes=off in a settings file stops recording.
offrepo="$area/offrepo"; new_repository "$offrepo"
settings set "$offrepo" escapes off --local >/dev/null
run_capturing bash "$add_script" "$offrepo" src/a wrong-result off --body-file "$area/body.md"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
[[ ! -e "$offrepo/.claude/mash-workbench/escapes" ]] || { echo "  recorded while off"; exit 1; }
