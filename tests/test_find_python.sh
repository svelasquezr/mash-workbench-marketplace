# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
finder=plugins/review-routing/scripts/python.sh
real_python=$(command -v python3)
bash_path=$(command -v bash)
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT

# Both plugins ship the same finder.
assert_eq "$(cmp plugins/review-routing/scripts/python.sh plugins/mash-workbench/scripts/python.sh && echo same)" "same"
# ... and the same settings lookup.
assert_eq "$(cmp plugins/review-routing/scripts/mash-settings.sh plugins/mash-workbench/scripts/mash-settings.sh && echo same)" "same"

# fake_bin <name>: a bin directory that holds only fakes, so the system python3 is out of sight.
# The stub also reads stdin, so a probe that does not shield stdin would lose the hook's input.
store_stub='#!/bin/sh
while read -r _; do :; done
echo "Python was not found; run without arguments to install from the Microsoft Store" >&2
exit 9009'
make_fake() { printf '%s\n' "$3" > "$1/$2"; chmod +x "$1/$2"; }
new_bin() { local d; d=$(mktemp -d "$scratch/bin.XXXXXX"); printf '%s' "$d"; }
run_finder() { local bin=$1; shift; run_capturing env -i HOME="$HOME" PATH="$bin" ${MASH_PYTHON+MASH_PYTHON="$MASH_PYTHON"} "$bash_path" "$finder" "$@"; }
printf 'import sys\nprint("ran", sys.argv[1:], sys.stdin.read().strip())\nsys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n' > "$scratch/echo.py"

# The Store stub answers for python3 and python; the launcher's "py -3" is used.
bin=$(new_bin)
make_fake "$bin" python3 "$store_stub"; make_fake "$bin" python "$store_stub"
make_fake "$bin" py "#!/bin/sh
[ \"\$1\" = -3 ] || exit 9
shift; exec \"$real_python\" \"\$@\""
run_finder "$bin" "$scratch/echo.py" 0 <<< '{"hook": "input"}'
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "ran ['0'] {\"hook\": \"input\"}"

# The script's exit code passes through.
for code in 1 2; do
  run_finder "$bin" "$scratch/echo.py" "$code" < /dev/null
  assert_eq "$captured_exit_code" "$code"
done

# A heredoc script ("-") works, as backlog-stale.sh uses it.
run_capturing env -i PATH="$bin" "$bash_path" "$finder" - arg <<< 'import sys; print("stdin script", sys.argv[1])'
assert_contains "$captured_output" "stdin script arg"

# MASH_PYTHON wins over the candidates, also as a path with a space in it.
mkdir -p "$scratch/Program Files"; ln -s "$real_python" "$scratch/Program Files/python"
bin=$(new_bin)
MASH_PYTHON="$scratch/Program Files/python" run_finder "$bin" "$scratch/echo.py" 0 < /dev/null
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "ran ['0']"

# A Python older than 3.11 is refused (the probe exits 1, as Python 3.10 would).
bin=$(new_bin)
make_fake "$bin" python3 '#!/bin/sh
exit 1'
run_finder "$bin" "$scratch/echo.py" 0 < /dev/null
assert_eq "$captured_exit_code" "3"

# No interpreter: exit 3 with a message that says what to do; --missing-ok exits 0 silently.
bin=$(new_bin)
make_fake "$bin" python3 "$store_stub"
run_finder "$bin" "$scratch/echo.py" 0 < /dev/null
assert_eq "$captured_exit_code" "3"
assert_contains "$captured_output" "no Python 3.11 or newer found"
assert_contains "$captured_output" "Microsoft Store"
assert_contains "$captured_output" "MASH_PYTHON"
run_finder "$bin" --missing-ok "$scratch/echo.py" 0 < /dev/null
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""

# Usage error.
run_finder "$bin"
assert_eq "$captured_exit_code" "2"
