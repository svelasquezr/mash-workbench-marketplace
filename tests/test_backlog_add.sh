# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
# The cases below write to the default file; the choice of file is tested at the end, with the variable unset.
export MASH_WORKBENCH_BACKLOG=docs/tooling-backlog.md
script=plugins/mash-workbench/skills/scout/backlog-add.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
output=$(BACKLOG_DATE=2026-10-04 bash "$script" "$temporary_directory" script "Check uv pin matches CI" "drifted twice")
assert_contains "$output" "added to backlog"
backlog_file="$temporary_directory/docs/tooling-backlog.md"
assert_contains "$(cat "$backlog_file")" "# Tooling backlog"
assert_contains "$(cat "$backlog_file")" "- [ ] 2026-10-04 · script · Check uv pin matches CI — drifted twice"
output=$(bash "$script" "$temporary_directory" hook "check UV pin matches ci" "again")
assert_contains "$output" "already in backlog"
assert_eq "$(grep -c '^- \[ \]' "$backlog_file")" "1"
set +e; bash "$script" "$temporary_directory" wizard "x" "y" 2>/dev/null; exit_code=$?; set -e
assert_eq "$exit_code" "2"
# Near duplicates (60% of the shorter title's words of 3+ letters, at least 2 shared) warn on stderr but are still added.
run_capturing bash "$script" "$temporary_directory" script "Check that the uv pin matches" "third time"
assert_contains "$captured_output" "near duplicate of: Check uv pin matches CI"
assert_contains "$captured_output" "added to backlog"
assert_eq "$captured_exit_code" "0"
assert_eq "$(grep -c '^- \[ \]' "$backlog_file")" "2"
# Unrelated titles, and titles sharing a single word, don't warn.
run_capturing bash "$script" "$temporary_directory" hook "Block force pushes to main" "twice"
assert_not_contains "$captured_output" "near duplicate"
run_capturing bash "$script" "$temporary_directory" script "Check docs links" "broke"
assert_not_contains "$captured_output" "near duplicate"
# Closed entries are not compared.
printf -- '- [x] 2026-10-01 · script · Rotate deploy keys monthly — done\n' >> "$backlog_file"
run_capturing bash "$script" "$temporary_directory" script "Rotate deploy keys" "again"
assert_not_contains "$captured_output" "near duplicate"
# Thresholds: exactly 60% of the shorter title (3 of 5 words) warns; 2 shared words of a 4-word title (50%) don't.
fresh_directory="$temporary_directory/fresh"; mkdir -p "$fresh_directory"
bash "$script" "$fresh_directory" script "alpha bravo charlie delta echo" "x" > /dev/null
run_capturing bash "$script" "$fresh_directory" script "alpha bravo charlie foxtrot golf hotel" "x"
assert_contains "$captured_output" "near duplicate of: alpha bravo charlie delta echo"
run_capturing bash "$script" "$fresh_directory" script "alpha bravo india juliet" "x"
assert_not_contains "$captured_output" "near duplicate"

# --- hostile or awkward input must not corrupt the backlog -------------------------------------------------------
fresh_backlog() { local d; d=$(mktemp -d "$temporary_directory/b.XXXXXX"); mkdir -p "$d/docs"; printf '%s' "$d"; }

# A newline in the title or the reason is folded into the one line; it never starts another entry or a heading.
root=$(fresh_backlog)
bash "$script" "$root" script $'Title\n- [ ] 2026-01-01 · hook · INJECTED fake' $'why\n# New heading' >/dev/null
assert_eq "$(grep -c '^- \[ \]' "$root/docs/tooling-backlog.md")" "1"
assert_eq "$(grep -c '^# New heading' "$root/docs/tooling-backlog.md")" "0"
assert_eq "$(grep -c '^- \[ \] 2026-01-01 · hook · INJECTED' "$root/docs/tooling-backlog.md")" "0"

# The date override must be a date.
root=$(fresh_backlog)
run_capturing env BACKLOG_DATE='not-a-date; rm -rf /' bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "BACKLOG_DATE"
assert_eq "$(grep -c '^- \[ \]' "$root/docs/tooling-backlog.md" 2>/dev/null || echo 0)" "0"

# A backlog that does not end in a newline: the next entry starts on its own line.
root=$(fresh_backlog)
printf '# Tooling backlog\n\n- [ ] 2026-01-01 · script · First entry — why' > "$root/docs/tooling-backlog.md"
bash "$script" "$root" script "Second entry" "other" >/dev/null
assert_eq "$(grep -c '^- \[ \]' "$root/docs/tooling-backlog.md")" "2"

# A CRLF backlog: a repeated title is still recognised.
root=$(fresh_backlog)
printf '# Tooling backlog\r\n\r\n- [ ] 2026-01-01 · script · First entry — why\r\n' > "$root/docs/tooling-backlog.md"
output=$(bash "$script" "$root" script "First entry" "again")
assert_contains "$output" "already in backlog"

# Backslashes in a title are kept as typed.
root=$(fresh_backlog)
bash "$script" "$root" script 'Check C:\new\table paths' "why" >/dev/null
assert_contains "$(cat "$root/docs/tooling-backlog.md")" 'Check C:\new\table paths'
assert_eq "$(grep -c '^- \[ \]' "$root/docs/tooling-backlog.md")" "1"

# A date must be a real date (calendar rules, without Python), a title must not be blank or hold the separator.
root=$(fresh_backlog)
for bad_date in 2026-13-45 2026-02-29 2026-04-31 2026-00-10 2100-02-29; do
  run_capturing env BACKLOG_DATE="$bad_date" bash "$script" "$root" script "A title" "why"
  assert_eq "$captured_exit_code" "2"
done
for good_date in 2028-02-29 2000-02-29; do
  root=$(fresh_backlog)
  BACKLOG_DATE="$good_date" bash "$script" "$root" script "A title" "why" >/dev/null
  assert_contains "$(cat "$root/docs/tooling-backlog.md")" "- [ ] $good_date · script · A title — why"
done
run_capturing bash "$script" "$root" script "   " "why"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$script" "$root" script "Alpha — beta" "why"
assert_eq "$captured_exit_code" "2"
# After --, everything is positional: a title that reads like a flag stays a title. An unknown option stops.
root=$(fresh_backlog)
bash "$script" "$root" script -- "--file" "why" >/dev/null
assert_contains "$(cat "$root/docs/tooling-backlog.md")" "· script · --file — why"
run_capturing bash "$script" --creat "$root" script "A title" "why"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "unknown option: --creat"
run_capturing bash "$script" "$root" script "A title"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "usage:"
# With python3 as the Windows Store stub (prints a message, exits 9009), an entry is still added.
stub_bin=$(mktemp -d "$temporary_directory/stub.XXXXXX")
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9009\n' > "$stub_bin/python3"
chmod +x "$stub_bin/python3"
root=$(fresh_backlog)
run_capturing env -u BACKLOG_DATE PATH="$stub_bin:$PATH" bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "0"
assert_contains "$(cat "$root/docs/tooling-backlog.md")" "- [ ] $(date -u +%F) · script · A title — why"

# --- which file: nothing is created before the user chose; the choice is a setting, never an argument --------------
source tests/git_fixtures.sh
path_script=plugins/mash-workbench/skills/scout/backlog-path.sh
stale_script=plugins/mash-workbench/skills/scout/backlog-stale.sh
settings_script="$PWD/plugins/mash-workbench/scripts/mash-settings.sh"
unset MASH_WORKBENCH_BACKLOG
# Outside a git repository only the environment variable and the old files answer.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
run_capturing bash "$path_script" "$root"
assert_eq "$captured_exit_code" "3"
run_capturing bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "MASH_WORKBENCH_BACKLOG"
assert_eq "$(find "$root" -mindepth 1 | wc -l | tr -d ' ')" "0"
run_capturing env MASH_WORKBENCH_BACKLOG=off bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
assert_eq "$(find "$root" -mindepth 1 | wc -l | tr -d ' ')" "0"
run_capturing env MASH_WORKBENCH_BACKLOG=off bash "$path_script" "$root"
assert_eq "$captured_exit_code" "4"

# The path checks refuse /tmp, so the git fixtures live under $HOME (never under /tmp).
fixture=$(mktemp -d "$HOME/.backlog-test.XXXXXX"); trap 'rm -rf "$temporary_directory" "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
fixture=$(cd "$fixture" && pwd -P)
saved_directory=$temporary_directory; temporary_directory="$fixture"; isolate_git_config; temporary_directory=$saved_directory
new_repo() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  echo ".claude/worktrees/" >> "$folder/.git/info/exclude"
  git -C "$folder" commit --quiet --allow-empty -m "chore: base"
  if [[ -n "${2:-}" ]]; then git -C "$folder" remote add origin "$2"; fi
  (cd "$folder" && pwd -P)
}
add() { bash "$script" "$@"; }

# Nothing chosen: exit 3 with the commands to run, and nothing is created.
repo=$(new_repo none git@github.com:Acme/Shop.git)
run_capturing add "$repo" script "A title" "why"
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "no tooling backlog chosen yet: ask the user where to keep it"
assert_contains "$captured_output" "mash-settings.sh set $repo backlog <path, or off> --team"
assert_contains "$captured_output" "mash-settings.sh set $repo backlog <path, or off> --local"
assert_contains "$captured_output" "The default is docs/mash/tooling-backlog.md"
assert_contains "$captured_output" "mash-settings.sh check-backlog-path $repo <path>"
assert_contains "$captured_output" "Setting up the backlog"
assert_not_contains "$captured_output" ".claude/settings.json"
[[ ! -e "$repo/docs" && ! -e "$repo/.claude" ]] || { echo "  created something before the user chose"; exit 1; }
# --create and --file are gone: no argument names the file to write.
for option in --create "--file $fixture/anywhere.md"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing add $option "$repo" script "A title" "why"
  assert_eq "$captured_exit_code" "2"
  assert_contains "$captured_output" "is gone"
  assert_contains "$captured_output" "mash-settings.sh set"
done
[[ ! -e "$fixture/anywhere.md" && ! -e "$repo/docs" ]] || { echo "  a gone option still wrote a file"; exit 1; }

# The commands the text prints work as printed: the default file gets a title, the owner line and the entry.
bash "$settings_script" set "$repo" backlog docs/mash/tooling-backlog.md --team >/dev/null
run_capturing env BACKLOG_DATE=2026-11-22 bash "$script" "$repo" script "A title" "why"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "added to backlog: A title"
assert_eq "$(head -n 2 "$repo/docs/mash/tooling-backlog.md")" "$(printf '# Tooling backlog\nrepo: github.com/acme/shop')"
assert_contains "$(cat "$repo/docs/mash/tooling-backlog.md")" "- [ ] 2026-11-22 · script · A title — why"
assert_eq "$(bash "$path_script" "$repo")" "$repo/docs/mash/tooling-backlog.md"

# The same answer from a linked worktree: the entry goes to the main worktree's file, and the worktree stays clean.
git -C "$repo" worktree add --quiet "$repo/.claude/worktrees/w1" -b w1
linked="$repo/.claude/worktrees/w1"
assert_eq "$(bash "$path_script" "$linked")" "$repo/docs/mash/tooling-backlog.md"
add "$linked" hook "From the worktree" "why" >/dev/null
assert_contains "$(cat "$repo/docs/mash/tooling-backlog.md")" "From the worktree"
assert_eq "$(git -C "$linked" status --porcelain)" ""
[[ ! -e "$linked/docs" ]] || { echo "  wrote into the linked worktree"; exit 1; }
assert_contains "$(BACKLOG_TODAY=2027-06-01 bash "$stale_script" "$linked")" "From the worktree"
# off in the settings: nothing is written and nothing is asked.
off_repo=$(new_repo off)
bash "$settings_script" set "$off_repo" backlog off --local >/dev/null
run_capturing add "$off_repo" script "A title" "why"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
[[ ! -e "$off_repo/docs" ]] || { echo "  wrote a backlog while it is off"; exit 1; }
assert_eq "$(bash "$stale_script" "$off_repo")" ""

# A backlog from before the setting existed keeps working where it is, from every worktree; the entry is added, the
# file gets its owner line, and stderr says how to give it a setting or move it.
legacy=$(new_repo legacy git@github.com:Acme/Shop.git)
mkdir -p "$legacy/docs"; printf '# Tooling backlog\n\n- [ ] 2026-01-01 · script · First entry — why\n' > "$legacy/docs/tooling-backlog.md"
git -C "$legacy" add docs; git -C "$legacy" commit --quiet -m "docs: backlog"
assert_eq "$(bash "$path_script" "$legacy")" "$legacy/docs/tooling-backlog.md"
run_capturing add "$legacy" hook "Old home" "why"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "added to backlog: Old home"
assert_contains "$captured_output" "has no setting yet"
assert_contains "$captured_output" "mash-settings.sh set $legacy backlog docs/tooling-backlog.md --team"
assert_contains "$captured_output" "git -C $legacy mv docs/tooling-backlog.md <new path>"
assert_eq "$(head -n 3 "$legacy/docs/tooling-backlog.md")" "$(printf '# Tooling backlog\nrepo: github.com/acme/shop\n')"
assert_eq "$(grep -c '^repo:' "$legacy/docs/tooling-backlog.md")" "1"
assert_eq "$(grep -c '^- \[ \]' "$legacy/docs/tooling-backlog.md")" "2"
[[ ! -e "$legacy/docs/mash" ]] || { echo "  created docs/mash next to an old backlog"; exit 1; }
# A second write adds no second owner line; after the setting exists, the hint is gone.
bash "$settings_script" set "$legacy" backlog docs/tooling-backlog.md --team >/dev/null
run_capturing add "$legacy" hook "Again" "why"
assert_not_contains "$captured_output" "no setting yet"
assert_eq "$(grep -c '^repo:' "$legacy/docs/tooling-backlog.md")" "1"
# With a setting that names a new file beside an old backlog, the path script warns.
bash "$settings_script" set "$legacy" backlog elsewhere.md --team >/dev/null
# shellcheck disable=SC2016
run_capturing bash -c 'bash "$1" "$2" 2>&1 >/dev/null' _ "$path_script" "$legacy"
assert_contains "$captured_output" "docs/tooling-backlog.md"
bash "$settings_script" unset "$legacy" backlog --team >/dev/null
# When both old files exist, the grouped one wins, and the path script says that two exist.
mkdir -p "$legacy/docs/mash"; printf '# Tooling backlog\n\n' > "$legacy/docs/mash/tooling-backlog.md"
assert_eq "$(bash "$path_script" "$legacy" 2>/dev/null)" "$legacy/docs/mash/tooling-backlog.md"
# shellcheck disable=SC2016
run_capturing bash -c 'bash "$1" "$2" 2>&1 >/dev/null' _ "$path_script" "$legacy"
assert_contains "$captured_output" "both"

# --- the file is never outside the places the user chose -----------------------------------------------------------
victim="$fixture/victim"; mkdir -p "$victim"; printf 'keep\n' > "$victim/startup-file"
# The committed team settings cannot name a file outside the repository.
team=$(new_repo team)
mkdir -p "$team/.claude/mash-workbench"
for outside in ../victim/startup-file "$victim/startup-file" ../victim/new.md; do
  printf 'backlog=%s\n' "$outside" > "$team/.claude/mash-workbench/settings"
  run_capturing add "$team" script "x; touch pwned #" "why"
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "outside the repository"
  run_capturing bash "$stale_script" "$team"
  assert_eq "$captured_exit_code" "6"
done
# The user's own settings.local, or the environment variable, may; the file's repo: line then names the owner.
bash "$settings_script" set "$team" backlog "$victim/own-backlog.md" --local >/dev/null
rm "$team/.claude/mash-workbench/settings"
add "$team" script "Mine" "why" >/dev/null
assert_contains "$(cat "$victim/own-backlog.md")" "repo: local/$(basename "$team" | tr '[:upper:]' '[:lower:]')"
other=$(new_repo other)
run_capturing env MASH_WORKBENCH_BACKLOG="$victim/own-backlog.md" bash "$script" "$other" script "Theirs" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "owned by"
assert_not_contains "$(cat "$victim/own-backlog.md")" "Theirs"
# The environment variable gets the same path checks: a temporary folder, a linked worktree and the git directory.
for bad in /tmp/backlog-test-$$.md "$linked/backlog.md" .git/backlog.md .; do
  run_capturing env MASH_WORKBENCH_BACKLOG="$bad" bash "$script" "$repo" script "A title" "why"
  assert_eq "$captured_exit_code" "6"
done
[[ ! -e "/tmp/backlog-test-$$.md" && ! -e "$linked/backlog.md" && ! -e "$repo/.git/backlog.md" ]] || { echo "  wrote to a refused place"; exit 1; }
# A committed symbolic link as the backlog file, as its folder, or as an old default file: nothing is appended, and a
# dangling link creates no file.
links=$(new_repo links)
mkdir -p "$links/docs"
ln -s "$victim/startup-file" "$links/docs/tooling-backlog.md"
run_capturing add "$links" script "x; touch pwned #" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
rm "$links/docs/tooling-backlog.md"; ln -s "$victim/created-by-link" "$links/docs/tooling-backlog.md"
run_capturing add "$links" script "A title" "why"
assert_eq "$captured_exit_code" "6"
run_capturing env MASH_WORKBENCH_BACKLOG=docs/tooling-backlog.md bash "$script" "$links" script "A title" "why"
assert_eq "$captured_exit_code" "6"
rm -r "$links/docs"; ln -s "$victim" "$links/docs"; printf '# Tooling backlog\n' > "$victim/tooling-backlog.md"
run_capturing add "$links" script "A title" "why"
assert_eq "$captured_exit_code" "6"
run_capturing env MASH_WORKBENCH_BACKLOG=docs/new.md bash "$script" "$links" script "A title" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
assert_eq "$(cat "$victim/startup-file")" "keep"
assert_eq "$(cat "$victim/tooling-backlog.md")" "# Tooling backlog"
[[ ! -e "$victim/created-by-link" && ! -e "$victim/new.md" ]] || { echo "  wrote through a symbolic link"; exit 1; }
# A settings.local that the repository committed is not the user's own file: in a fresh clone it cannot send the
# backlog line to a file outside the repository (a shell startup file, for example).
committed=$(new_repo committed-local)
mkdir -p "$committed/.claude/mash-workbench"
printf 'backlog=%s\n' "$victim/startup-file" > "$committed/.claude/mash-workbench/settings.local"
git -C "$committed" add -f .claude/mash-workbench/settings.local
git -C "$committed" commit --quiet -m "chore: a committed settings.local"
git clone --quiet "$committed" "$fixture/committed-clone"
run_capturing add "$fixture/committed-clone" script "x; touch pwned;" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "outside the repository"
assert_eq "$(cat "$victim/startup-file")" "keep"
# "<no such name>/../<committed link>" in the committed settings: refused, nothing appended outside.
dots=$(new_repo dots); mkdir -p "$dots/.claude/mash-workbench" "$victim/.claude"
printf 'keep\n' > "$victim/.claude/CLAUDE.md"; ln -s ../victim/.claude "$dots/link"
printf 'backlog=nope2/../link/CLAUDE.md\n' > "$dots/.claude/mash-workbench/settings"
run_capturing add "$dots" script "Always run tool X" "why"
assert_eq "$captured_exit_code" "6"
assert_eq "$(cat "$victim/.claude/CLAUDE.md")" "keep"
# Outside a git repository there are no path checks, but a linked folder must not move the write out of <repo-root>.
plain=$(mktemp -d "$temporary_directory/plain.XXXXXX"); mkdir -p "$temporary_directory/plain-victim"
ln -s "$temporary_directory/plain-victim" "$plain/docs"
run_capturing env MASH_WORKBENCH_BACKLOG=docs/notes.md bash "$script" "$plain" script "A title" "why"
assert_eq "$captured_exit_code" "6"
[[ ! -e "$temporary_directory/plain-victim/notes.md" ]] || { echo "  wrote through a linked folder outside git"; exit 1; }
# A committed setting can name any file inside the repository. The script writes only to a new file, an empty file,
# or a file whose first line is the backlog title: a .env or a source file gets no line.
other_file=$(new_repo other-file); mkdir -p "$other_file/.claude/mash-workbench"
printf 'API_KEY=abc\n' > "$other_file/.env"
printf 'backlog=.env\n' > "$other_file/.claude/mash-workbench/settings"
run_capturing add "$other_file" script "A title" "why"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "# Tooling backlog"
assert_eq "$(cat "$other_file/.env")" "API_KEY=abc"
# An empty file is a new backlog; a backlog with a CRLF title is a backlog.
: > "$other_file/notes.md"; printf 'backlog=notes.md\n' > "$other_file/.claude/mash-workbench/settings"
add "$other_file" script "A title" "why" >/dev/null
assert_eq "$(head -n 1 "$other_file/notes.md")" "# Tooling backlog"
printf '# Tooling backlog\r\n\r\n' > "$other_file/crlf.md"; printf 'backlog=crlf.md\n' > "$other_file/.claude/mash-workbench/settings"
add "$other_file" script "A title" "why" >/dev/null
assert_contains "$(cat "$other_file/crlf.md")" "A title"
