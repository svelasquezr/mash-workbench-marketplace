# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
add=plugins/review-routing/skills/add-reviewer/escape-add.sh
report=plugins/review-routing/skills/add-reviewer/escapes-report.sh
path_script=plugins/review-routing/skills/add-reviewer/escapes-path.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
unset REVIEW_ROUTING_ESCAPES
fresh() { mktemp -d "$temporary_directory/$1.XXXXXX"; }

# Nothing chosen and no ledger: the path script exits 3, nothing is created, and the message says how to choose.
root=$(fresh none)
run_capturing bash "$path_script" "$root"
assert_eq "$captured_exit_code" "3"
run_capturing bash "$add" "$root" src/payments wrong-result "https://example.test/issues/1"
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "--create"
assert_contains "$captured_output" "--file"
assert_contains "$captured_output" "REVIEW_ROUTING_ESCAPES"
assert_contains "$captured_output" "docs/mash/review-escapes.md"
assert_contains "$captured_output" ".gitignore"
[[ ! -e "$root/docs" ]] || { echo "  created docs/ before the user chose"; exit 1; }
# The report has nothing to count and says so.
run_capturing bash "$report" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no escapes recorded"

# --create starts the grouped default; afterwards it is used without asking.
bash "$add" --create "$root" src/payments wrong-result "https://example.test/issues/1" >/dev/null
assert_contains "$(cat "$root/docs/mash/review-escapes.md")" "· src/payments · wrong-result ·"
bash "$add" "$root" src/payments missing-test "https://example.test/issues/2" >/dev/null
assert_eq "$(grep -c '^- ' "$root/docs/mash/review-escapes.md")" "2"
assert_eq "$(bash "$path_script" "$root")" "$(cd "$root" && pwd -P)/docs/mash/review-escapes.md"
run_capturing bash "$report" "$root"
assert_contains "$captured_output" "src/payments: 2 escapes"

# --file keeps the ledger elsewhere.
root=$(fresh file)
bash "$add" --file notes/escapes.md "$root" src/a wrong-result "https://example.test/issues/3" >/dev/null
assert_contains "$(cat "$root/notes/escapes.md")" "· src/a · wrong-result ·"
[[ ! -e "$root/docs" ]] || { echo "  created docs/ next to --file"; exit 1; }

# The setting moves the ledger (relative to the repository root) and "off" records nothing.
root=$(fresh setting)
REVIEW_ROUTING_ESCAPES=quality/escapes.md bash "$add" "$root" src/a wrong-result "https://example.test/issues/4" >/dev/null
assert_contains "$(cat "$root/quality/escapes.md")" "src/a"
REVIEW_ROUTING_ESCAPES=quality/escapes.md run_capturing bash "$report" "$root"
assert_contains "$captured_output" "src/a: 1 escape"
root=$(fresh off)
REVIEW_ROUTING_ESCAPES=off run_capturing bash "$path_script" "$root"
assert_eq "$captured_exit_code" "4"
REVIEW_ROUTING_ESCAPES=off run_capturing bash "$add" "$root" src/a wrong-result "https://example.test/issues/5"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "off"
[[ ! -e "$root/docs" ]] || { echo "  created docs/ while off"; exit 1; }
REVIEW_ROUTING_ESCAPES=off run_capturing bash "$report" "$root"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no escapes recorded"

# A project that already has docs/review-escapes.md keeps it; the grouped file wins when both exist.
root=$(fresh legacy)
mkdir -p "$root/docs"; printf '# Review escapes\n\n' > "$root/docs/review-escapes.md"
assert_eq "$(bash "$path_script" "$root")" "$(cd "$root" && pwd -P)/docs/review-escapes.md"
bash "$add" "$root" src/a wrong-result "https://example.test/issues/6" >/dev/null
assert_contains "$(cat "$root/docs/review-escapes.md")" "src/a"
[[ ! -e "$root/docs/mash" ]] || { echo "  created docs/mash next to a legacy ledger"; exit 1; }
mkdir -p "$root/docs/mash"; printf '# Review escapes\n\n' > "$root/docs/mash/review-escapes.md"
assert_eq "$(bash "$path_script" "$root")" "$(cd "$root" && pwd -P)/docs/mash/review-escapes.md"

# --file with a second entry in the same area still prints the "add a reviewer" line from that file.
root=$(fresh filereport)
bash "$add" --file notes/escapes.md "$root" src/a wrong-result "https://example.test/issues/7" >/dev/null
run_capturing bash "$add" --file notes/escapes.md "$root" src/a missing-test "https://example.test/issues/8"
assert_contains "$captured_output" "add a reviewer for src/a"
