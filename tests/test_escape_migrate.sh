# shellcheck shell=bash
# escape-migrate.sh: the old one-line-per-escape ledger becomes one file per escape; the old file stays for the user.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
migrate="$PWD/plugins/review-routing/skills/add-reviewer/escape-migrate.sh"
report="$PWD/plugins/review-routing/skills/add-reviewer/escapes-report.sh"
add="$PWD/plugins/review-routing/skills/add-reviewer/escape-add.sh"
settings_script="$PWD/plugins/review-routing/scripts/mash-settings.sh"
# The path checks refuse /tmp, so the fixture lives under $HOME (never under /tmp).
fixture=$(mktemp -d "$HOME/.escape-migrate-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$fixture"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES
escapes_folder=.claude/mash-workbench/escapes
fresh() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  git -C "$folder" commit --quiet --allow-empty -m "chore: base"
  (cd "$folder" && pwd -P)
}
count_files() { find "$1" -maxdepth 1 -name '*.md' ! -name README.md 2>/dev/null | wc -l | tr -d ' '; }
# old_ledger <file>: three entries (CRLF, no final newline), a duplicate link, prose and a malformed entry line.
old_ledger() {
  mkdir -p "$(dirname "$1")"
  printf -- '# Review escapes\r\n\r\nBugs in code a review passed.\r\n- a note in prose\r\n- 2026-10-11 · src/a · wrong-result · https://github.com/o/r/issues/1\r\n- 2026-10-12 · src/a/ · missing-test · https://github.com/o/r/issues/2\r\n- 2026-10-12 · src/a · wrong-result · https://github.com/o/r/issues/1\r\n- 2026-10-13 · src/a · broken\r\n- 2026-10-14 · docs · stale-doc · https://example.test/bugs/3' > "$1"
}

# 10. A committed docs/mash/review-escapes.md: 3 entries become 3 files in the default folder; a second run adds none.
root=$(fresh committed)
old_ledger "$root/docs/mash/review-escapes.md"
git -C "$root" add docs; git -C "$root" commit --quiet -m "docs: old ledger"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded 3, already recorded 1"
assert_contains "$captured_output" "skipped line 8 of docs/mash/review-escapes.md"
assert_contains "$captured_output" "git -C $root rm docs/mash/review-escapes.md"
assert_contains "$captured_output" "mash-settings.sh set $root escapes .claude/mash-workbench/escapes --team"
assert_eq "$(count_files "$root/$escapes_folder")" "3"
assert_eq "$(cat "$root/$escapes_folder/2026-10-11-migrated-1.md")" "$(printf -- '---\ndate: 2026-10-11\narea: src/a\nclass: wrong-result\nsource: https://github.com/o/r/issues/1\n---\n\nMigrated; see source.')"
assert_contains "$(cat "$root/$escapes_folder/2026-10-12-migrated-2.md")" "area: src/a"
assert_contains "$(cat "$root/$escapes_folder/2026-10-14-migrated-4.md")" "source: https://example.test/bugs/3"
assert_file "$root/$escapes_folder/README.md"
assert_file "$root/docs/mash/review-escapes.md"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded 0, already recorded 4"
assert_eq "$(count_files "$root/$escapes_folder")" "3"
# After the printed steps, the report counts the files and recording works.
git -C "$root" rm --quiet docs/mash/review-escapes.md
bash "$settings_script" set "$root" escapes "$escapes_folder" --team >/dev/null
assert_eq "$(bash "$report" "$root")" "$(printf '%s\n' 'src/a: 2 escapes (wrong-result 1, missing-test 1)' 'docs: 1 escape (stale-doc 1)')"
assert_eq "$(bash "$in_root_script" "$add" --list "$root" src/a)" "$(printf '%s\n' '2026-10-12-migrated-2.md  Migrated; see source.' '2026-10-11-migrated-1.md  Migrated; see source.')"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no old ledger found"

# An untracked docs/review-escapes.md: the command is plain rm, and the new folder comes from the escapes setting.
root=$(fresh untracked)
old_ledger "$root/docs/review-escapes.md"
bash "$settings_script" set "$root" escapes "$fixture/kept-escapes" --local >/dev/null
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "rm $root/docs/review-escapes.md"
assert_not_contains "$captured_output" "git -C"
assert_not_contains "$captured_output" "mash-settings.sh set"
assert_eq "$(count_files "$fixture/kept-escapes")" "3"
assert_contains "$(cat "$fixture/kept-escapes/README.md")" "repo: local/untracked."

# REVIEW_ROUTING_ESCAPES names the old file: the default folder is used, and the output says to set the folder and drop
# the variable, which would otherwise keep winning over the settings files.
root=$(fresh env-file)
old_ledger "$root/notes/escapes.md"
run_capturing env REVIEW_ROUTING_ESCAPES=notes/escapes.md bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_eq "$(count_files "$root/$escapes_folder")" "3"
assert_contains "$captured_output" "mash-settings.sh set $root escapes .claude/mash-workbench/escapes --team"
assert_contains "$captured_output" "remove REVIEW_ROUTING_ESCAPES from .claude/settings*.json"
assert_contains "$captured_output" "rm $root/notes/escapes.md"
# The setting names the old file: the same, without the variable line.
root=$(fresh setting-file)
old_ledger "$root/notes/escapes.md"
bash "$settings_script" set "$root" escapes notes/escapes.md --local >/dev/null
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$(count_files "$root/$escapes_folder")" "3"
assert_contains "$captured_output" "mash-settings.sh set $root escapes .claude/mash-workbench/escapes"
assert_not_contains "$captured_output" "REVIEW_ROUTING_ESCAPES"
# Both old default files: both are migrated in one run.
root=$(fresh both)
old_ledger "$root/docs/review-escapes.md"
printf -- '- 2026-10-20 · src/b · data-loss · https://github.com/o/r/issues/9\n' > "$root/docs/review-escapes2.md"
mkdir -p "$root/docs/mash"; mv "$root/docs/review-escapes2.md" "$root/docs/mash/review-escapes.md"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_contains "$captured_output" "recorded 4, already recorded 1"
assert_contains "$captured_output" "rm $root/docs/mash/review-escapes.md"
assert_contains "$captured_output" "rm $root/docs/review-escapes.md"

# One link in two areas is two escapes, as the old report counted it: both lines become files.
root=$(fresh two-areas)
mkdir -p "$root/docs"
printf -- '- 2026-10-11 · src/a · wrong-result · https://github.com/o/r/issues/1\n- 2026-10-12 · src/b · wrong-result · https://github.com/o/r/issues/1\n' > "$root/docs/review-escapes.md"
old_report=$(bash "$report" "$root" 2>/dev/null)
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_contains "$captured_output" "recorded 2, already recorded 0"
bash "$settings_script" set "$root" escapes "$escapes_folder" --local >/dev/null
rm "$root/docs/review-escapes.md"
assert_eq "$(bash "$report" "$root")" "$old_report"
# The migrated numbers run on across the old files, so the names do not depend on which file a line came from.
assert_file "$root/$escapes_folder/2026-10-12-migrated-2.md"

# An entry that fails escape-add.sh's checks is named by its old file and line; nothing is written.
root=$(fresh bad-entry)
mkdir -p "$root/docs"
printf -- '# Review escapes\n- 2026-10-11 · src/a · wrong-result · https://github.com/o/r/issues/1\n- 2026-10-12 · src/a · Bad Class · https://github.com/o/r/issues/2\n' > "$root/docs/review-escapes.md"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "docs/review-escapes.md:3: the class is lowercase words"
assert_not_contains "$captured_output" "block"
[[ ! -e "$root/$escapes_folder" ]] || { echo "  migrated part of a ledger with a bad entry"; exit 1; }

# Paths in the printed commands are quoted: the rm line works as printed for a path with a space.
root=$(fresh "with space")
old_ledger "$root/docs/review-escapes.md"
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_contains "$captured_output" "rm $(printf '%q' "$root/docs/review-escapes.md")"
assert_contains "$captured_output" "set $(printf '%q' "$root") escapes"
eval "$(printf '%s\n' "$captured_output" | awk '/^  rm / { sub(/^  /, ""); print }')"
[[ ! -e "$root/docs/review-escapes.md" ]] || { echo "  the printed rm command did not work"; exit 1; }

# Off: nothing is migrated (exit 4). Another repository's folder: refused (exit 6). No old ledger: nothing to do.
root=$(fresh off)
old_ledger "$root/docs/review-escapes.md"
bash "$settings_script" set "$root" escapes off --local >/dev/null
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "4"
[[ ! -e "$root/.claude/mash-workbench/escapes" ]] || { echo "  migrated while off"; exit 1; }
root=$(fresh owned)
old_ledger "$root/docs/review-escapes.md"
mkdir -p "$fixture/owned-escapes"; printf '# Review escapes\nrepo: github.com/other/thing\n' > "$fixture/owned-escapes/README.md"
bash "$settings_script" set "$root" escapes "$fixture/owned-escapes" --local >/dev/null
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "6"
assert_eq "$(count_files "$fixture/owned-escapes")" "0"
root=$(fresh nothing)
run_capturing bash "$in_root_script" "$migrate" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no old ledger found"
# Usage errors.
run_capturing bash "$in_root_script" "$migrate"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$migrate" "$fixture/missing"
assert_eq "$captured_exit_code" "2"
not_repo=$(mktemp -d "$fixture/not-repo.XXXXXX")
run_capturing bash "$in_root_script" "$migrate" "$not_repo"
assert_eq "$captured_exit_code" "2"
