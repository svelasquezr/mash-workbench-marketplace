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

# --- which file: nothing is created before the user chose; the choice can be another path, or none ----------------
path_script=plugins/mash-workbench/skills/scout/backlog-path.sh
unset MASH_WORKBENCH_BACKLOG
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
run_capturing bash "$path_script" "$root"
assert_eq "$captured_exit_code" "3"
run_capturing bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "--create"
assert_contains "$captured_output" "--file"
assert_contains "$captured_output" "MASH_WORKBENCH_BACKLOG"
assert_contains "$captured_output" ".claude/settings.local.json"
[[ ! -e "$root/docs" ]] || { echo "  created docs/ before the user chose"; exit 1; }

# --create: the default file.
bash "$script" --create "$root" script "A title" "why" >/dev/null
assert_contains "$(cat "$root/docs/tooling-backlog.md")" "· script · A title — why"
# Once it exists it is used without asking, and backlog-path.sh prints it.
bash "$script" "$root" hook "Another title" "why" >/dev/null
assert_eq "$(grep -c '^- \[ \]' "$root/docs/tooling-backlog.md")" "2"
assert_eq "$(bash "$path_script" "$root")" "$(cd "$root" && pwd -P)/docs/tooling-backlog.md"

# --file: another file, created there and nowhere else.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
bash "$script" --file notes/tooling.md "$root" script "A title" "why" >/dev/null
assert_contains "$(cat "$root/notes/tooling.md")" "· script · A title — why"
[[ ! -e "$root/docs" ]] || { echo "  --file also created docs/"; exit 1; }

# MASH_WORKBENCH_BACKLOG (set through the env block of .claude/settings.local.json): a path, relative to the root.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
MASH_WORKBENCH_BACKLOG=notes/other.md bash "$script" "$root" script "A title" "why" >/dev/null
assert_contains "$(cat "$root/notes/other.md")" "A title"
assert_eq "$(MASH_WORKBENCH_BACKLOG=notes/other.md bash "$path_script" "$root")" "$(cd "$root" && pwd -P)/notes/other.md"
# off: the project keeps none; nothing is written and nothing is asked.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
run_capturing env MASH_WORKBENCH_BACKLOG=off bash "$script" "$root" script "A title" "why"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
assert_eq "$(find "$root" -mindepth 1 | wc -l | tr -d ' ')" "0"
run_capturing env MASH_WORKBENCH_BACKLOG=off bash "$path_script" "$root"
assert_eq "$captured_exit_code" "4"

# A flag works in any position (a session that appends it still gets what it asked for).
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
bash "$script" "$root" script "Flag last" "why" --create >/dev/null
assert_contains "$(cat "$root/docs/tooling-backlog.md")" "Flag last"
# The exit-3 message shows the whole command to re-run.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
run_capturing bash "$script" "$root" script "A title" "why"
assert_contains "$captured_output" "backlog-add.sh --create <repo-root>"
# off wins over --create and --file: a file nobody would read again is never written.
run_capturing env MASH_WORKBENCH_BACKLOG=off bash "$script" --create "$root" script "A title" "why"
assert_eq "$captured_exit_code" "0"
[[ ! -e "$root/docs" ]] || { echo "  wrote a backlog while it is off"; exit 1; }
# A date must be a real date, a title must not be blank or hold the separator.
run_capturing env BACKLOG_DATE=2026-13-45 bash "$script" --create "$root" script "A title" "why"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$script" --create "$root" script "   " "why"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$script" --create "$root" script "Alpha — beta" "why"
assert_eq "$captured_exit_code" "2"

# After --, everything is positional: a title that reads like a flag stays a title.
root=$(mktemp -d "$temporary_directory/choice.XXXXXX")
bash "$script" --create "$root" script -- "--file" "why" >/dev/null
assert_contains "$(cat "$root/docs/tooling-backlog.md")" "· script · --file — why"

# --file with no value, and an unknown option, stop with the usage line.
run_capturing bash "$script" "$root" script "A title" "why" --file
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "usage:"
run_capturing bash "$script" --creat "$root" script "A title" "why"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "unknown option: --creat"
