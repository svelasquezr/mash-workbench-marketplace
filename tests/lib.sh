# shellcheck shell=bash
# Minimal assertions for bash tests. Each test file is run in its own bash process.
assert_eq() { if [[ "$1" != "$2" ]]; then printf '  expected: %s\n  actual:   %s\n' "$2" "$1"; exit 1; fi; }
assert_contains() { if [[ "$1" != *"$2"* ]]; then printf '  expected to contain: %s\n  in: %s\n' "$2" "$1"; exit 1; fi; }
assert_file() { [[ -f "$1" ]] || { echo "  missing file: $1"; exit 1; }; }
# run_capturing <command...>: runs it without exiting on failure; sets captured_output (stdout+stderr) and captured_exit_code.
# shellcheck disable=SC2034
run_capturing() { set +e; captured_output=$("$@" 2>&1); captured_exit_code=$?; set -e; }
assert_not_contains() { if [[ "$1" == *"$2"* ]]; then printf '  expected NOT to contain: %s\n  in: %s\n' "$2" "$1"; exit 1; fi; }
