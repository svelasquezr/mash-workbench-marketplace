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
bash "$add_script" "$led_linked" src/a wrong-result one --body "$(cat "$area/body.md")" >/dev/null
run_capturing bash "$add_script" "$led_linked" src/a missing-test two --body "$(cat "$area/body.md")"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded: .claude/mash-workbench/escapes/"
assert_eq "$(find "$led/.claude/mash-workbench/escapes" -name '*.md' ! -name README.md | wc -l | tr -d ' ')" "2"
[[ ! -e "$led_linked/.claude/mash-workbench" ]] || { echo "  recorded into the linked worktree"; exit 1; }
assert_contains "$(bash "$report_script" "$led_linked" 2>/dev/null)" "src/a: 2 escapes"

# Finding 11: escapes=off in a settings file stops recording.
offrepo="$area/offrepo"; new_repository "$offrepo"
settings set "$offrepo" escapes off --local >/dev/null
run_capturing bash "$add_script" "$offrepo" src/a wrong-result off --body "$(cat "$area/body.md")"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
[[ ! -e "$offrepo/.claude/mash-workbench/escapes" ]] || { echo "  recorded while off"; exit 1; }

# An empty value counts as not set, for every key: get skips it (the next source answers), set refuses it.
empty_repo="$area/empty"; new_repository "$empty_repo"; mkdir -p "$empty_repo/.claude/mash-workbench"
printf 'k=\n' > "$empty_repo/.claude/mash-workbench/settings.local"
run_capturing settings get "$empty_repo" k
assert_eq "$captured_exit_code" "3"
printf 'k=team\n' > "$empty_repo/.claude/mash-workbench/settings"
assert_eq "$(settings get "$empty_repo" k)" "team"
run_capturing settings set "$empty_repo" k "" --local
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "unset"
assert_eq "$(settings get "$empty_repo" k)" "team"
# check-escapes-path refuses the repository root itself.
for root_path in "$empty_repo" "$empty_repo/" . ./; do
  run_capturing settings check-escapes-path "$empty_repo" "$root_path"
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "the escapes folder must not be the repository root"
done
run_capturing settings check-escapes-path "$empty_repo" docs/escapes
assert_eq "$captured_exit_code" "0"

# A value of only spaces or tabs counts as empty: get skips it, set refuses it.
printf 'w= \nv=\t\n' > "$empty_repo/.claude/mash-workbench/settings.local"
run_capturing settings get "$empty_repo" w
assert_eq "$captured_exit_code" "3"
run_capturing settings get "$empty_repo" v
assert_eq "$captured_exit_code" "3"
for blank in " " $'\t'; do
  run_capturing settings set "$empty_repo" w "$blank" --local
  assert_eq "$captured_exit_code" "2"
  assert_contains "$captured_output" "unset"
done
# The last line of a key wins within a file: a later empty line hides an earlier value, and the next source answers.
printf 'last=early\nlast=\n' > "$empty_repo/.claude/mash-workbench/settings.local"
printf 'last=team\n' > "$empty_repo/.claude/mash-workbench/settings"
assert_eq "$(settings get "$empty_repo" last)" "team"

# 12. source: where get's value comes from.
src_repo="$area/source"; new_repository "$src_repo"; mkdir -p "$src_repo/.claude/mash-workbench"
run_capturing settings source "$src_repo" escapes
assert_eq "$captured_exit_code" "3"
printf 'escapes=a\n' > "$src_repo/.claude/mash-workbench/settings"
assert_eq "$(settings source "$src_repo" escapes)" "team"
printf 'escapes=b\n' > "$src_repo/.claude/mash-workbench/settings.local"
assert_eq "$(settings source "$src_repo" escapes)" "local"
assert_eq "$(REVIEW_ROUTING_ESCAPES=c settings source "$src_repo" escapes)" "env"
# An empty local value does not answer, so the team file is the source.
printf 'escapes=\n' > "$src_repo/.claude/mash-workbench/settings.local"
assert_eq "$(settings source "$src_repo" escapes)" "team"

# 13. path: the folder or file a key names, and who may choose a place outside the repository.
path_repo="$area/pathrepo"; new_repository "$path_repo"; mkdir -p "$path_repo/.claude/mash-workbench" "$area/victim/.claude"
path_main=$(normalized "$path_repo")
team="$path_repo/.claude/mash-workbench/settings"; local_file="$path_repo/.claude/mash-workbench/settings.local"
run_capturing settings path "$path_repo" escapes
assert_eq "$captured_exit_code" "3"
printf 'escapes=off\n' > "$team"
run_capturing settings path "$path_repo" escapes
assert_eq "$captured_exit_code" "4"
printf 'escapes=.claude/mash-workbench/escapes\nbacklog=docs/mash/tooling-backlog.md\n' > "$team"
assert_eq "$(settings path "$path_repo" escapes)" "$path_main/.claude/mash-workbench/escapes"
assert_eq "$(settings path "$path_repo" backlog)" "$path_main/docs/mash/tooling-backlog.md"
# The committed team file cannot choose a place outside the main worktree: relative with .., or absolute.
for outside in ../victim/.claude/rules "$area/victim/.claude/rules"; do
  for key in escapes backlog; do
    printf '%s=%s\n' "$key" "$outside" > "$team"
    run_capturing settings path "$path_repo" "$key"
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "outside the repository"
    assert_contains "$captured_output" "--local"
  done
done
# The same place from settings.local (the user's own file) or from the environment variable is accepted.
printf 'escapes=../victim/.claude/rules\n' > "$local_file"
assert_eq "$(settings path "$path_repo" escapes)" "$area/victim/.claude/rules"
rm "$local_file"
assert_eq "$(REVIEW_ROUTING_ESCAPES="$area/victim/x" settings path "$path_repo" escapes)" "$area/victim/x"
assert_eq "$(MASH_WORKBENCH_BACKLOG="$area/victim/b.md" settings path "$path_repo" backlog)" "$area/victim/b.md"
# The repository root itself is refused, whoever chose it.
printf 'escapes=.\n' > "$local_file"
run_capturing settings path "$path_repo" escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "repository root"
# A path written inside the repository whose symbolic link leads outside is refused for every source: a committed link
# must not move the writes of a user who chose a folder inside the repository.
ln -s "$area/victim" "$path_repo/.claude/mash-workbench/escapes"
printf 'escapes=.claude/mash-workbench/escapes\n' > "$local_file"
run_capturing settings path "$path_repo" escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
run_capturing env REVIEW_ROUTING_ESCAPES=.claude/mash-workbench/escapes bash "$settings_script" path "$path_repo" escapes
assert_eq "$captured_exit_code" "6"
run_capturing settings check-escapes-path "$path_repo" .claude/mash-workbench/escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
rm "$path_repo/.claude/mash-workbench/escapes" "$local_file"
# A link that stays inside the repository is fine.
mkdir -p "$path_repo/docs/real"; ln -s real "$path_repo/docs/link"
printf 'escapes=docs/link\n' > "$team"
assert_eq "$(settings path "$path_repo" escapes)" "$path_main/docs/link"
# Unknown keys have no path.
run_capturing settings path "$path_repo" escapes.threshold
assert_eq "$captured_exit_code" "2"

# 14. A symbolic link at the home folder is refused: a committed link would move the settings and the review log.
link_repo="$area/linkhome"; new_repository "$link_repo"; mkdir -p "$link_repo/.claude" "$area/elsewhere"
printf 'escapes=x\n' > "$area/elsewhere/settings"
ln -s "$area/elsewhere" "$link_repo/.claude/mash-workbench"
for arguments in "home $link_repo" "get $link_repo escapes" "source $link_repo escapes" "path $link_repo escapes" \
  "set $link_repo escapes x --local" "set $link_repo escapes x --team" "unset $link_repo escapes --team"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing settings $arguments
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "symbolic link"
done
assert_eq "$(cat "$area/elsewhere/settings")" "escapes=x"
assert_eq "$(find "$area/elsewhere" -type f | wc -l | tr -d ' ')" "1"
# The environment variable still answers get: it reads no file.
assert_eq "$(REVIEW_ROUTING_ESCAPES=/somewhere settings get "$link_repo" escapes)" "/somewhere"
# A link inside the repository is refused too (the home folder is one real folder), and so is a linked .claude that
# leads outside.
rm "$link_repo/.claude/mash-workbench"; mkdir -p "$link_repo/other"; ln -s ../other "$link_repo/.claude/mash-workbench"
run_capturing settings home "$link_repo"
assert_eq "$captured_exit_code" "6"
rm -r "$link_repo/.claude"; mkdir -p "$area/elsewhere/claude"; ln -s "$area/elsewhere/claude" "$link_repo/.claude"
run_capturing settings set "$link_repo" escapes x --local
assert_eq "$captured_exit_code" "6"
assert_eq "$(find "$area/elsewhere/claude" -type f | wc -l | tr -d ' ')" "0"

# 15. check-backlog-path: the rules of check-escapes-path, for a file.
back_repo="$area/backrepo"; new_repository "$back_repo"; git -C "$back_repo" remote add origin git@github.com:Acme/Shop.git
run_capturing settings check-backlog-path "$back_repo" docs/mash/tooling-backlog.md
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "inside the repo"
run_capturing settings check-backlog-path "$back_repo" .
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "the backlog file must not be the repository root"
mkdir -p "$back_repo/docs/folder"
run_capturing settings check-backlog-path "$back_repo" docs/folder
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "is a folder"
run_capturing settings check-backlog-path "$back_repo" /tmp/backlog.md
assert_eq "$captured_exit_code" "6"
run_capturing settings check-backlog-path "$back_repo" .git/backlog.md
assert_eq "$captured_exit_code" "6"
# A symbolic link as the file is refused: an append would follow it.
printf 'x\n' > "$area/elsewhere/target.md"; ln -s "$area/elsewhere/target.md" "$back_repo/docs/linked.md"
run_capturing settings check-backlog-path "$back_repo" docs/linked.md
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
# Outside the repository, the file's own repo: line names its owner.
printf '# Tooling backlog\nrepo: github.com/other/thing\n' > "$area/elsewhere/backlog.md"
run_capturing settings check-backlog-path "$back_repo" "$area/elsewhere/backlog.md"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "owned by github.com/other/thing"
printf '# Tooling backlog\nrepo: GitHub.com/Acme/Shop\n' > "$area/elsewhere/backlog.md"
run_capturing settings check-backlog-path "$back_repo" "$area/elsewhere/backlog.md"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "outside the repo"
# A dangling symbolic link as the escapes folder is refused too.
ln -s "$area/elsewhere/nowhere" "$back_repo/docs/dangling"
run_capturing settings check-escapes-path "$back_repo" docs/dangling
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"

# 16. settings.local is the user's own file only when git does not track it. A repository can commit one: a fresh
#     clone then has it, and it must not be able to choose a place outside the repository.
tracked="$area/tracked"; new_repository "$tracked"; mkdir -p "$tracked/.claude/mash-workbench"
printf 'escapes=%s\nbacklog=%s\n' "$area/victim/.claude/rules" "$area/victim/startup-file" > "$tracked/.claude/mash-workbench/settings.local"
git -C "$tracked" add -f .claude/mash-workbench/settings.local
git -C "$tracked" commit --quiet -m "chore: a committed settings.local"
git clone --quiet "$tracked" "$area/tracked-clone"
for copy in "$tracked" "$area/tracked-clone"; do
  assert_eq "$(settings source "$copy" escapes)" "team"
  for key in escapes backlog; do
    run_capturing settings path "$copy" "$key"
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "outside the repository"
  done
done
# set --local refuses to write a tracked settings.local: the value would be committed with it.
run_capturing settings set "$area/tracked-clone" escapes x --local
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "tracked"
# The same file, not tracked (the normal case), is the user's own.
git -C "$tracked" rm --quiet --cached .claude/mash-workbench/settings.local
git -C "$tracked" commit --quiet -m "chore: untrack"
assert_eq "$(settings source "$tracked" escapes)" "local"
assert_eq "$(settings path "$tracked" escapes)" "$area/victim/.claude/rules"

# 17. A settings file that is a symbolic link is never read and never written through: a committed link to a private
#     file would copy that file into the settings, and a link to a folder would send the write there.
linked_settings="$area/linked-settings"; new_repository "$linked_settings"; mkdir -p "$linked_settings/.claude/mash-workbench" "$area/private"
printf 'SECRET-KEY-MATERIAL\nescapes=stolen\n' > "$area/private/key"
for name in settings settings.local; do
  ln -s "$area/private/key" "$linked_settings/.claude/mash-workbench/$name"
  for arguments in "get $linked_settings escapes" "source $linked_settings escapes" "path $linked_settings escapes" \
    "set $linked_settings escapes x --team" "set $linked_settings escapes x --local" "unset $linked_settings escapes --team" "unset $linked_settings escapes --local"; do
    # shellcheck disable=SC2086  # the words are split on purpose
    run_capturing settings $arguments
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "symbolic link"
    assert_not_contains "$captured_output" "SECRET"
  done
  [[ -L "$linked_settings/.claude/mash-workbench/$name" ]] || { echo "  a linked settings file was replaced"; exit 1; }
  rm "$linked_settings/.claude/mash-workbench/$name"
done
ln -s "$area/private" "$linked_settings/.claude/mash-workbench/settings.local"
run_capturing settings set "$linked_settings" escapes.threshold 3 --local
assert_eq "$captured_exit_code" "6"
assert_eq "$(cat "$area/private/key")" "$(printf 'SECRET-KEY-MATERIAL\nescapes=stolen')"
assert_eq "$(find "$area/private" -mindepth 1 | wc -l | tr -d ' ')" "1"
rm "$linked_settings/.claude/mash-workbench/settings.local"

# 18. A value with a backslash is refused: the path code splits on "/" only, so "C:\Users\x" or "..\..\x" would pass
#     as a name inside the repository, and Git Bash reads it as a path.
slash_repo="$area/backslash"; new_repository "$slash_repo"; mkdir -p "$slash_repo/.claude/mash-workbench"
for value in 'C:\Users\victim\.claude\rules' '..\..\victim\file'; do
  printf 'escapes=%s\nbacklog=%s\n' "$value" "$value" > "$slash_repo/.claude/mash-workbench/settings"
  for key in escapes backlog; do
    run_capturing settings path "$slash_repo" "$key"
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "backslash"
  done
  run_capturing settings check-escapes-path "$slash_repo" "$value"
  assert_eq "$captured_exit_code" "6"
  run_capturing settings check-backlog-path "$slash_repo" "$value"
  assert_eq "$captured_exit_code" "6"
done
# /var/tmp is a temporary folder too.
run_capturing settings check-escapes-path "$slash_repo" /var/tmp/escapes
assert_eq "$captured_exit_code" "6"

# 19. "<a name that does not exist>/../<committed link>": removing ".." as text must not hide the link. The path that
#     is checked is the path that is printed and written, with no ".." in it.
dots="$area/dots"; new_repository "$dots"; mkdir -p "$dots/.claude/mash-workbench" "$area/victim/.claude"
ln -s ../victim/.claude "$dots/link"
dots_main=$(normalized "$dots")
for source_file in settings settings.local; do
  printf 'escapes=nope/../link/rules\nbacklog=nope2/../link/CLAUDE.md\n' > "$dots/.claude/mash-workbench/$source_file"
  for key in escapes backlog; do
    run_capturing settings path "$dots" "$key"
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "symbolic link"
  done
  rm "$dots/.claude/mash-workbench/$source_file"
done
for value in nope/../link/rules link/rules "$dots/nope/../link/rules"; do
  run_capturing settings check-escapes-path "$dots" "$value"
  assert_eq "$captured_exit_code" "6"
  run_capturing settings check-backlog-path "$dots" "$value"
  assert_eq "$captured_exit_code" "6"
done
# What path prints holds no "..": the same text goes to the checks and to the write.
printf 'escapes=a/../b/./c\n' > "$dots/.claude/mash-workbench/settings"
assert_eq "$(settings path "$dots" escapes)" "$dots_main/b/c"
printf 'escapes=../outside-escapes\n' > "$dots/.claude/mash-workbench/settings.local"
assert_eq "$(settings path "$dots" escapes)" "$(dirname "$dots_main")/outside-escapes"
# A tracked settings.local in another letter case (a file system that ignores case opens it) is still tracked.
git -C "$dots" add -f .claude/mash-workbench/settings.local; git -C "$dots" commit --quiet -m "chore: local"
git -C "$dots" mv .claude/mash-workbench/settings.local .claude/mash-workbench/SETTINGS.LOCAL 2>/dev/null || true
if [[ -f "$dots/.claude/mash-workbench/SETTINGS.LOCAL" && ! -f "$dots/.claude/mash-workbench/settings.local" ]]; then
  cp "$dots/.claude/mash-workbench/SETTINGS.LOCAL" "$dots/.claude/mash-workbench/settings.local"
  assert_eq "$(settings source "$dots" escapes)" "team"
fi
# 20. A local path as the origin gives local/<folder>, not the path: the key goes into files that people commit.
keyrepo="$area/keyrepo"; new_repository "$keyrepo"
for url in "$area/some/origin.git" ../origin "file://$area/some/origin.git"; do
  git -C "$keyrepo" remote remove origin 2>/dev/null || true
  git -C "$keyrepo" remote add origin "$url"
  assert_eq "$(settings repo-key "$keyrepo")" "local/keyrepo"
done

# 21. A committed settings.local reached in a way that the main worktree's index does not show at the literal path.
#     In each case the file is not the user's own: source prints team, and a place outside the repository is refused.
# a. The repository commits .claude as a symbolic link to a folder that holds mash-workbench/settings.local. The home
#    folder must be the real <main>/.claude/mash-workbench, so every command that reads or writes it stops.
via_link="$area/via-link"; new_repository "$via_link"; mkdir -p "$via_link/stuff/mash-workbench"
printf 'escapes=../victim/.claude/rules\n' > "$via_link/stuff/mash-workbench/settings.local"
ln -s stuff "$via_link/.claude"
git -C "$via_link" add -f .claude stuff; git -C "$via_link" commit --quiet -m "chore: a linked .claude"
git clone --quiet "$via_link" "$area/via-link-clone"
for arguments in "source $area/via-link-clone escapes" "path $area/via-link-clone escapes" "get $area/via-link-clone escapes" \
  "home $area/via-link-clone" "set $area/via-link-clone escapes.threshold 4 --local"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing settings $arguments
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "symbolic link"
done
assert_eq "$(cat "$area/via-link-clone/stuff/mash-workbench/settings.local")" "escapes=../victim/.claude/rules"
# b. .claude/mash-workbench is a submodule that holds settings.local: the file is tracked, in another repository.
sub_source="$area/sub-source"; new_repository "$sub_source"
printf 'escapes=../victim/.claude/rules\n' > "$sub_source/settings.local"
git -C "$sub_source" add settings.local; git -C "$sub_source" commit --quiet -m "chore: settings"
with_sub="$area/with-sub"; new_repository "$with_sub"
git -C "$with_sub" -c protocol.file.allow=always submodule --quiet add "$sub_source" .claude/mash-workbench
git -C "$with_sub" commit --quiet -m "chore: a submodule as the home folder"
git -c protocol.file.allow=always clone --quiet --recurse-submodules "$with_sub" "$area/with-sub-clone" 2>/dev/null
assert_file "$area/with-sub-clone/.claude/mash-workbench/settings.local"
assert_eq "$(settings source "$area/with-sub-clone" escapes)" "team"
run_capturing settings path "$area/with-sub-clone" escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "outside the repository"
run_capturing settings set "$area/with-sub-clone" escapes.threshold 4 --local
assert_eq "$captured_exit_code" "6"
assert_eq "$(cat "$area/with-sub-clone/.claude/mash-workbench/settings.local")" "escapes=../victim/.claude/rules"
# An untracked file in a nested repository that is not this repository is not this user's private file either.
nested="$area/nested"; new_repository "$nested"; mkdir -p "$nested/.claude/mash-workbench"
git init --quiet "$nested/.claude/mash-workbench"
printf 'escapes=../victim/.claude/rules\n' > "$nested/.claude/mash-workbench/settings.local"
assert_eq "$(settings source "$nested" escapes)" "team"
# c. GIT_LITERAL_PATHSPECS (and the other pathspec variables) in the user's environment do not change the answer.
plain_tracked="$area/plain-tracked"; new_repository "$plain_tracked"; mkdir -p "$plain_tracked/.claude/mash-workbench"
printf 'escapes=../outside\n' > "$plain_tracked/.claude/mash-workbench/settings.local"
git -C "$plain_tracked" add -f .claude/mash-workbench/settings.local; git -C "$plain_tracked" commit --quiet -m "chore: local"
for variable in GIT_LITERAL_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS; do
  assert_eq "$(env "$variable=1" bash "$settings_script" source "$plain_tracked" escapes)" "team"
  run_capturing env "$variable=1" bash "$settings_script" path "$plain_tracked" escapes
  assert_eq "$captured_exit_code" "6"
done
# An index that the environment names (an empty one) does not make the file private.
assert_eq "$(env GIT_INDEX_FILE="$area/empty-index" bash "$settings_script" source "$plain_tracked" escapes)" "team"
# The normal case still works: an untracked settings.local in the repository's own home folder is the user's.
own="$area/own"; new_repository "$own"
settings set "$own" escapes ../own-outside --local >/dev/null
assert_eq "$(settings source "$own" escapes)" "local"
assert_eq "$(GIT_LITERAL_PATHSPECS=1 settings source "$own" escapes)" "local"
assert_eq "$(settings path "$own" escapes)" "$area/own-outside"

# 22. A drive-letter path keeps its spelling: the refusal of a backslash tells the user to write C:/..., and that
#     text must come back as written, not as /C:/...
settings set "$own" escapes 'C:/Users/me/x/../escapes' --local >/dev/null
assert_eq "$(settings path "$own" escapes)" "C:/Users/me/escapes"
assert_eq "$(REVIEW_ROUTING_ESCAPES='d:/a/./b' settings path "$own" escapes)" "d:/a/b"
settings set "$own" escapes ../own-outside --local >/dev/null
