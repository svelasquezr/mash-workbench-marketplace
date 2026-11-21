# shellcheck shell=bash
# Choosing and finding the escapes folder: escape-add.sh asks before anything exists, honours "off", writes into the
# main worktree from a linked one, and refuses to write beside an old one-file ledger.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
add="$PWD/plugins/review-routing/skills/add-reviewer/escape-add.sh"
report="$PWD/plugins/review-routing/skills/add-reviewer/escapes-report.sh"
path_script="$PWD/plugins/review-routing/skills/add-reviewer/escapes-path.sh"
settings_script="$PWD/plugins/review-routing/scripts/mash-settings.sh"
# The path checks refuse /tmp, so the fixture lives under $HOME (never under /tmp).
fixture=$(mktemp -d "$HOME/.ledger-location-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$fixture"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES
fresh() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  git -C "$folder" commit --quiet --allow-empty -m "chore: base"
  (cd "$folder" && pwd -P)
}
body="$fixture/body.md"; printf 'When X, Y happens.\nZ must happen.\n' > "$body"
record() { local repo=$1; shift; bash "$add" "$repo" src/a wrong-result "$1" --body-file "$body" "${@:2}"; }

# 13. Nothing chosen: escape-add.sh exits 3 with the setup text and creates nothing; the report and --list say "none".
root=$(fresh none)
run_capturing bash "$path_script" "$root"
assert_eq "$captured_exit_code" "3"
run_capturing record "$root" first
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "no escapes folder chosen yet: ask the user where to keep it"
assert_contains "$captured_output" "mash-settings.sh set $root escapes <path, or off> --team   (committed escapes)"
assert_contains "$captured_output" "mash-settings.sh set $root escapes <path, or off> --local  (excluded, or outside the repo)"
assert_contains "$captured_output" "The default is .claude/mash-workbench/escapes"
assert_contains "$captured_output" "mash-settings.sh check-escapes-path $root <path>"
assert_contains "$captured_output" "Setting up escapes"
[[ ! -e "$root/.claude" ]] || { echo "  created .claude/ before the user chose"; exit 1; }
run_capturing bash "$report" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no escapes recorded"
run_capturing bash "$add" --list "$root" src/a
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "no escapes in src/a"
printf -- '---\narea: src/a\nclass: c\nslug: s\n---\nx\n' > "$fixture/batch.txt"
run_capturing bash "$add" --batch "$fixture/batch.txt" "$root"
assert_eq "$captured_exit_code" "3"
[[ ! -e "$root/.claude" ]] || { echo "  --batch created .claude/ before the user chose"; exit 1; }
# The commands the text prints work as printed: choosing the default records into it.
settings_command=$(printf '%s\n' "$captured_output" | awk '/--local  \(excluded/ { sub(/^ +bash /, ""); sub(/ set .*/, ""); print }')
bash "$settings_command" set "$root" escapes .claude/mash-workbench/escapes --local >/dev/null
run_capturing record "$root" first
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded: .claude/mash-workbench/escapes/"

# Paths in the printed commands are quoted, so a repository path with a space still works when pasted as printed.
root=$(fresh "with space")
run_capturing record "$root" first
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "set $(printf '%q' "$root") escapes"
local_line=$(printf '%s\n' "$captured_output" | awk '/--local  \(excluded/ { sub(/^ +/, ""); sub(/  \(excluded.*/, ""); print }')
eval "${local_line/<path, or off>/.claude/mash-workbench/escapes}" >/dev/null
run_capturing record "$root" first
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded: .claude/mash-workbench/escapes/"

# A setting that names a missing .md file is an old ledger path, not a folder to create.
root=$(fresh md-setting)
run_capturing env REVIEW_ROUTING_ESCAPES=quality/escapes.md bash "$add" "$root" src/a wrong-result md --body-file "$body"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "this looks like an old ledger file: $root/quality/escapes.md; point the setting at a folder"
[[ ! -e "$root/quality" ]] || { echo "  created a folder named like a ledger file"; exit 1; }

# "off", from the settings files or the environment, records nothing and exits 0.
root=$(fresh off)
bash "$settings_script" set "$root" escapes off --team >/dev/null
for command in record "env REVIEW_ROUTING_ESCAPES=off bash $add --batch $fixture/batch.txt"; do
  if [[ "$command" == record ]]; then run_capturing record "$root" off; else
    # shellcheck disable=SC2086  # split on purpose
    run_capturing $command "$root"
  fi
  assert_eq "$captured_exit_code" "0"
  assert_contains "$captured_output" "the escapes ledger is off for this project: nothing recorded"
done
[[ ! -e "$root/.claude/mash-workbench/escapes" ]] || { echo "  recorded while off"; exit 1; }
run_capturing bash "$report" "$root"
assert_contains "$captured_output" "no escapes recorded"

# A linked worktree records into the main worktree's folder, and its own status stays clean.
root=$(fresh linked)
printf '.claude/worktrees/\n' >> "$root/.git/info/exclude"
git -C "$root" worktree add --quiet .claude/worktrees/w -b w
linked="$root/.claude/worktrees/w"
bash "$settings_script" set "$root" escapes .claude/mash-workbench/escapes --local >/dev/null
run_capturing record "$linked" from-linked
assert_eq "$captured_exit_code" "0"
assert_eq "$(find "$root/.claude/mash-workbench/escapes" -name '*-from-linked.md' | wc -l | tr -d ' ')" "1"
[[ ! -e "$linked/.claude/mash-workbench" ]] || { echo "  wrote into the linked worktree"; exit 1; }
assert_eq "$(git -C "$linked" status --porcelain)" ""
assert_contains "$(bash "$report" "$linked")" "src/a: 1 escape"
assert_contains "$(bash "$add" --list "$linked" src/a)" "-from-linked.md  When X, Y happens."
# A folder inside a linked worktree is refused: it is deleted with its branch.
run_capturing env REVIEW_ROUTING_ESCAPES="$linked/escapes" bash "$add" "$root" src/a wrong-result in-linked --body-file "$body"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "linked worktree"
[[ ! -e "$linked/escapes" ]] || { echo "  created a folder in a linked worktree"; exit 1; }
# A temporary folder is refused before anything is created.
run_capturing env REVIEW_ROUTING_ESCAPES="/tmp/ledger-location-$$/escapes" bash "$add" "$root" src/a wrong-result in-tmp --body-file "$body"
assert_eq "$captured_exit_code" "6"
[[ ! -e "/tmp/ledger-location-$$" ]] || { echo "  created a folder under /tmp"; exit 1; }
# An absolute folder outside the repo under $HOME works, and gets this repository's README.md.
run_capturing env REVIEW_ROUTING_ESCAPES="$fixture/outside/escapes" bash "$add" "$root" src/a wrong-result outside --body-file "$body"
assert_eq "$captured_exit_code" "0"
assert_contains "$(cat "$fixture/outside/escapes/README.md")" "repo: local/linked."

# 12. An old one-file ledger in place: escape-add.sh exits 3 with the migration message and writes nothing.
for old in docs/mash/review-escapes.md docs/review-escapes.md; do
  root=$(fresh old)
  mkdir -p "$root/$(dirname "$old")"
  printf '# Review escapes\n\n- 2026-01-01 · src/a · wrong-result · https://example.test/issues/1\n' > "$root/$old"
  before=$(cat "$root/$old")
  run_capturing record "$root" beside-old
  assert_eq "$captured_exit_code" "3"
  assert_contains "$captured_output" "old ledger format at $root/$old: ask the user, then run escape-migrate.sh"
  assert_eq "$(cat "$root/$old")" "$before"
  [[ ! -e "$root/.claude" ]] || { echo "  wrote beside an old ledger"; exit 1; }
  run_capturing bash "$add" --list "$root" src/a
  assert_eq "$captured_exit_code" "3"
  # The path script names the old file and points at the migration.
  # shellcheck disable=SC2016  # the single quotes are meant: $1 and $2 expand in the inner bash
  run_capturing bash -c 'bash "$1" "$2" 2>&1 >/dev/null' _ "$path_script" "$root"
  assert_contains "$captured_output" "old ledger format in use: $old"
  assert_contains "$captured_output" "escape-migrate.sh"
done
# The same when REVIEW_ROUTING_ESCAPES names a file.
root=$(fresh env-file)
printf '# Review escapes\n' > "$root/escapes.md"
run_capturing env REVIEW_ROUTING_ESCAPES=escapes.md bash "$add" "$root" src/a wrong-result env-file --body-file "$body"
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "escape-migrate.sh"
assert_eq "$(cat "$root/escapes.md")" "# Review escapes"
# A folder setting beside an old ledger records into the folder, and the path script warns about the old file.
root=$(fresh beside)
mkdir -p "$root/docs"; printf '# Review escapes\n' > "$root/docs/review-escapes.md"
bash "$settings_script" set "$root" escapes .claude/mash-workbench/escapes --local >/dev/null
run_capturing record "$root" beside
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "docs/review-escapes.md holds escapes in the old format"
assert_contains "$captured_output" "escape-migrate.sh"

# The report still counts an old ledger until it is migrated, and says so on stderr.
root=$(fresh old-report)
mkdir -p "$root/docs"
printf -- '# Review escapes\r\n- a note in prose, not an entry\r\n- 2026-10-11 · ./src/a/ · wrong-result · https://example.test/issues/1\r\n- 2026-10-12 · src/a · wrong-result · https://example.test/issues/1\r\n- 2026-10-12 · src/a · data-loss · https://example.test/issues/2\r\n- 2026-10-13 · src/a · data-loss · https://example.test/issues/3' > "$root/docs/review-escapes.md"
assert_eq "$(bash "$report" "$root" 2>/dev/null)" "src/a: 3 escapes (wrong-result 1, data-loss 2) -> add a reviewer for src/a (add-reviewer skill)"
# shellcheck disable=SC2016  # the single quotes are meant: $1 and $2 expand in the inner bash
run_capturing bash -c 'bash "$1" "$2" 2>&1 >/dev/null' _ "$report" "$root"
assert_contains "$captured_output" "old ledger format: run escape-migrate.sh"
printf '# Review escapes\n\n' > "$root/docs/review-escapes.md"
assert_eq "$(bash "$report" "$root" 2>/dev/null)" "no escapes recorded"

# --create and --file are gone, and say what replaced them; outside a git repository nothing is recorded.
root=$(fresh gone)
for option in --create --file; do
  run_capturing bash "$add" "$option" "$root" src/a wrong-result s --body-file "$body"
  assert_eq "$captured_exit_code" "2"
  assert_contains "$captured_output" "mash-settings.sh"
done
not_repo=$(mktemp -d "$fixture/not-repo.XXXXXX")
run_capturing env REVIEW_ROUTING_ESCAPES="$fixture/not-repo-escapes" bash "$add" "$not_repo" src/a wrong-result s --body-file "$body"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "not in a git repository"
[[ ! -e "$fixture/not-repo-escapes" ]] || { echo "  recorded outside a git repository"; exit 1; }
run_capturing bash "$path_script" "$fixture/missing"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$add" "$fixture/missing" src/a wrong-result s --body-file "$body"
assert_eq "$captured_exit_code" "2"
