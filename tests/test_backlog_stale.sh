# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
script=plugins/mash-workbench/skills/scout/backlog-stale.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
# No backlog: nothing printed, exit 0.
run_capturing bash "$script" "$temporary_directory"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""
mkdir -p "$temporary_directory/docs"
cat > "$temporary_directory/docs/tooling-backlog.md" <<'MD'
# Tooling backlog

- [ ] 2026-10-15 · script · Recent item — new
- [ ] 2026-08-01 · hook · Oldest item — old
- [x] 2026-07-01 · script · Closed item — done
- [ ] 2026-09-10 · skill · Middle item — older
MD
output=$(BACKLOG_TODAY=2026-10-21 bash "$script" "$temporary_directory")
assert_eq "$output" "$(printf '2026-08-01 (81 days) · hook · Oldest item\n2026-09-10 (41 days) · skill · Middle item')"
output=$(BACKLOG_TODAY=2026-10-21 bash "$script" "$temporary_directory" 3)
assert_contains "$output" "Recent item"
assert_eq "$(wc -l <<< "$output" | tr -d ' ')" "3"
run_capturing bash "$script" "$temporary_directory" soon
assert_eq "$captured_exit_code" "2"
# A header-only or all-closed backlog (the state after a /forge) prints nothing and exits 0.
printf '# Tooling backlog\n\n' > "$temporary_directory/docs/tooling-backlog.md"
run_capturing bash "$script" "$temporary_directory"
assert_eq "$captured_exit_code" "0"; assert_eq "$captured_output" ""
printf -- '- [x] 2026-01-01 · script · Done — x\n' >> "$temporary_directory/docs/tooling-backlog.md"
run_capturing bash "$script" "$temporary_directory"
assert_eq "$captured_exit_code" "0"; assert_eq "$captured_output" ""
# Exactly <days> old is not older; days=0 lists anything before today. An impossible or missing date is listed as
# undated, after the dated ones, and doesn't stop the listing. Years sort correctly.
cat > "$temporary_directory/docs/tooling-backlog.md" <<'MD'
- [ ] 2026-02-30 · script · Bad date — x
- [ ] 2026-10-11 · script · Ten days — x
- [ ] Hand-written entry — x
- [ ] 2025-12-31 · hook · Last year — x
- [ ] 2026-10-21 · hook · Today — x
MD
output=$(BACKLOG_TODAY=2026-10-21 bash "$script" "$temporary_directory" 10)
assert_eq "$output" "$(printf '2025-12-31 (294 days) · hook · Last year\nundated · 2026-02-30 · script · Bad date\nundated · Hand-written entry')"
output=$(BACKLOG_TODAY=2026-10-21 bash "$script" "$temporary_directory" 0)
assert_contains "$output" "Ten days"; assert_not_contains "$output" "Today"
run_capturing env BACKLOG_TODAY=someday bash "$script" "$temporary_directory"
assert_eq "$captured_exit_code" "2"

# The backlog the project chose: MASH_WORKBENCH_BACKLOG names another file, or off (nothing to list).
chosen=$(mktemp -d)
mkdir -p "$chosen/notes"
printf -- '- [ ] 2026-01-01 · script · Old entry — why\n' > "$chosen/notes/tooling.md"
output=$(MASH_WORKBENCH_BACKLOG=notes/tooling.md BACKLOG_TODAY=2026-10-01 bash "$script" "$chosen")
assert_contains "$output" "Old entry"
output=$(MASH_WORKBENCH_BACKLOG=off BACKLOG_TODAY=2026-10-01 bash "$script" "$chosen")
assert_eq "$output" ""
rm -rf "$chosen"

# A root that does not exist is an error, not "nothing stale".
run_capturing bash "$script" /no/such/root
[[ "$captured_exit_code" != 0 ]] || { echo "  a missing root exited 0"; exit 1; }
