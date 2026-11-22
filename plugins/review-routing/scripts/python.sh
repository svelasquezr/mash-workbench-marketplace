#!/usr/bin/env bash
# Run a Python script with the first working Python 3.11 or newer:
#   $MASH_PYTHON (a command, such as "py -3.12" or a full path), then python3, then python, then the Windows launcher "py -3".
# Each candidate must answer a version probe (run with -I as well, so the probe imports nothing from the project). On Windows, python3 and python are often the Microsoft Store
# alias: it prints "Python was not found" and exits 9009, so the probe skips it.
# Stdin and the script's exit code pass through (exec). The probe reads nothing from stdin, so hook input is kept.
# No interpreter: exit 3 with a message on stderr, or exit 0 and print nothing with --missing-ok (the hooks).
# The interpreter runs isolated, with -I -B (and PYTHONSAFEPATH=1 and PYTHONDONTWRITEBYTECODE=1 for a Python that a
# script starts): it does not import from the current folder or from the script's folder, it ignores PYTHONPATH and
# the other PYTHON* variables and the user site-packages, and it writes no __pycache__. So a project that holds a
# datetime.py or a re.py cannot run code in a plugin script. A script that needs its own folder adds it itself
# (reviewers-for-change.py does). MASH_PYTHON is a command that this file runs: whoever sets it chooses what runs.
# The same file ships in each MASH plugin (an installed plugin cannot read another plugin's files);
# tests/test_find_python.sh keeps the copies equal.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONSAFEPATH=1
usage="usage: python.sh [--missing-ok] <script.py | -> [arguments...]"
missing_ok=""
if [[ "${1:-}" == --missing-ok ]]; then missing_ok=1; shift; fi
if [[ $# -lt 1 ]]; then echo "$usage" >&2; exit 2; fi
probe='import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'
candidates=()
if [[ -n "${MASH_PYTHON:-}" ]]; then candidates+=("$MASH_PYTHON"); fi
candidates+=("python3" "python" "py -3")
for candidate in "${candidates[@]}"; do
  if [[ -f "$candidate" ]]; then command_words=("$candidate")  # a path, possibly with spaces
  else read -r -a command_words <<< "$candidate"; fi
  [[ ${#command_words[@]} -gt 0 ]] || continue
  command -v "${command_words[0]}" >/dev/null 2>&1 || continue
  if "${command_words[@]}" -I -c "$probe" </dev/null >/dev/null 2>&1; then
    exec "${command_words[@]}" -I -B "$@"
  fi
done
if [[ -n "$missing_ok" ]]; then exit 0; fi
{
  echo "python.sh: no Python 3.11 or newer found. Tried: ${MASH_PYTHON:+MASH_PYTHON ($MASH_PYTHON), }python3, python, py -3."
  echo "On Windows, the Microsoft Store alias (\"Python was not found\") does not count: install Python 3.11+ from python.org,"
  echo "or set MASH_PYTHON to a working interpreter, in the env block of .claude/settings.local.json: {\"env\": {\"MASH_PYTHON\": \"py -3.12\"}}"
} >&2
exit 3
