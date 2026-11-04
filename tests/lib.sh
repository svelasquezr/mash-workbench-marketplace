# shellcheck shell=bash
# Minimal assertions for bash tests. Each test file is run in its own bash process.
assert_eq() { if [[ "$1" != "$2" ]]; then printf '  expected: %s\n  actual:   %s\n' "$2" "$1"; exit 1; fi; }
assert_contains() { if [[ "$1" != *"$2"* ]]; then printf '  expected to contain: %s\n  in: %s\n' "$2" "$1"; exit 1; fi; }
assert_not_contains() { if [[ "$1" == *"$2"* ]]; then printf '  expected NOT to contain: %s\n  in: %s\n' "$2" "$1"; exit 1; fi; }
