# shellcheck shell=bash
# scripts/eval.sh <plugin> runs `claude plugin eval` on a copy of plugins/<plugin> that holds the cases from
# evals/<plugin>/, passes extra arguments through, keeps the exit code, copies results back, and leaves the plugin
# folder without an evals/ folder. It refuses a plugin name that is not a plain folder name. A fake `claude` on PATH records what it was given.
set -euo pipefail
source tests/lib.sh
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT

# A copy of the repository parts the script needs.
repo="$scratch/repo"
mkdir -p "$repo/scripts" "$repo/plugins/mash-review/skills/review" "$repo/evals/mash-review/01-case/graders" "$repo/evals/mash-review/results/old"
cp scripts/eval.sh "$repo/scripts/"
printf 'skill\n' > "$repo/plugins/mash-review/skills/review/SKILL.md"
printf 'name: 01-case\n' > "$repo/evals/mash-review/01-case/case.yaml"
printf 'x\n' > "$repo/evals/mash-review/results/old/stale.json"

# The fake claude: records its arguments and the files of the plugin copy, writes a result, exits with $FAKE_EXIT.
mkdir -p "$scratch/bin"
cat > "$scratch/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG"
target=$3
(cd "$target" && find . -type f | sort) > "$FAKE_LOG.files"
mkdir -p "$target/evals/results/run1"
printf 'ok\n' > "$target/evals/results/run1/aggregate-result.json"
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$scratch/bin/claude"

run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" bash "$repo/scripts/eval.sh" mash-review --case '01-*'
assert_eq "$captured_exit_code" "0"
assert_eq "$(sed -n 1,2p "$scratch/log" | tr '\n' ' ')" "plugin eval "
assert_contains "$(cat "$scratch/log")" "--scaffold"
assert_contains "$(cat "$scratch/log")" "01-*"
# The copy holds the plugin and the case, not the old results.
assert_contains "$(cat "$scratch/log.files")" "./skills/review/SKILL.md"
assert_contains "$(cat "$scratch/log.files")" "./evals/01-case/case.yaml"
assert_not_contains "$(cat "$scratch/log.files")" "stale.json"
# Results come back; the plugin folder gets no evals/ folder.
assert_eq "$(cat "$repo/evals/mash-review/results/run1/aggregate-result.json")" "ok"
[[ ! -e "$repo/plugins/mash-review/evals" ]] || { echo "  the script wrote evals/ into the plugin folder"; exit 1; }

# The exit code of claude passes through.
run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" FAKE_EXIT=1 bash "$repo/scripts/eval.sh" mash-review
assert_eq "$captured_exit_code" "1"

# A missing, empty or path-like plugin name: exit 2 with a message, and claude never runs.
rm -f "$scratch/log"
mkdir -p "$repo/plugins/x" "$repo/evals/x"
for name in "" "../mash-review" "mash-review/x" "-x" ".." "x y"; do
  run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" bash "$repo/scripts/eval.sh" "$name"
  assert_eq "$captured_exit_code" "2"
  assert_contains "$captured_output" "usage: "
done
run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" bash "$repo/scripts/eval.sh"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "usage: "
[[ ! -e "$scratch/log" ]] || { echo "  claude ran for a refused plugin name"; exit 1; }

# Without the cases folder: exit 2 and a message.
rm -rf "$repo/evals"
run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" bash "$repo/scripts/eval.sh" mash-review
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "evals/mash-review"

# Another plugin works the same way.
mkdir -p "$repo/plugins/mash-workbench/skills/scout" "$repo/evals/mash-workbench/01-w"
printf 'skill\n' > "$repo/plugins/mash-workbench/skills/scout/SKILL.md"
printf 'name: 01-w\n' > "$repo/evals/mash-workbench/01-w/case.yaml"
run_capturing env PATH="$scratch/bin:$PATH" FAKE_LOG="$scratch/log" bash "$repo/scripts/eval.sh" mash-workbench
assert_eq "$captured_exit_code" "0"
assert_contains "$(cat "$scratch/log.files")" "./evals/01-w/case.yaml"
assert_eq "$(cat "$repo/evals/mash-workbench/results/run1/aggregate-result.json")" "ok"
