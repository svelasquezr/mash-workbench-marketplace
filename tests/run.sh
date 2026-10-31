#!/usr/bin/env bash
# Runs every tests/test_*.sh, TEST_JOBS at a time (default: one per CPU). Each file's output is kept together and
# printed, in file order, followed by PASS or FAIL for it. Exits 1 if any file failed.
# Pros of running in parallel: wall clock drops to about the slowest file. Cons: the test files must not share
# state (each uses its own mktemp directory), and a file's output appears only once all files have finished.
# A test that kills its runner with a signal can make xargs stop early; the files that never reported are then shown
# as FAIL even if they would have passed (never a false PASS). Uses only POSIX-and-BSD-safe tools (ls -S, tr, xargs -0 -P).
set -euo pipefail
cd "$(dirname "$0")/.."
jobs_count="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
results_directory=$(mktemp -d); trap 'rm -rf "$results_directory"' EXIT

# shellcheck disable=SC2329  # called by the bash that xargs starts (exported below)
# run_one <test file>: runs it with its output in a results file and records its exit code next to it.
run_one() {
  local test_file="$1" results_directory="$2" result_name
  result_name=$(basename "$test_file" .sh)
  if bash "$test_file" > "$results_directory/$result_name.out" 2>&1; then
    echo 0 > "$results_directory/$result_name.status"
  else
    echo 1 > "$results_directory/$result_name.status"
  fi
}
export -f run_one

# Largest files first: they are the slow ones, so starting them early keeps a long file from running alone at the end.
# shellcheck disable=SC2016  # the single quotes are on purpose: the inner bash expands $1 and $2
# shellcheck disable=SC2012  # the names are test_*.sh: no spaces or newlines to trip ls
ls -S tests/test_*.sh | tr '\n' '\0' \
  | xargs -0 -I{} -P "$jobs_count" bash -c 'run_one "$1" "$2"' _ {} "$results_directory" || true

failed=0
for test_file in tests/test_*.sh; do
  result_name=$(basename "$test_file" .sh)
  # A file that never recorded a status (the runner itself broke) counts as failed.
  status=$(cat "$results_directory/$result_name.status" 2>/dev/null || echo 1)
  cat "$results_directory/$result_name.out" 2>/dev/null || true
  if [[ "$status" == 0 ]]; then echo "PASS $test_file"; else echo "FAIL $test_file"; failed=1; fi
done
exit $failed
