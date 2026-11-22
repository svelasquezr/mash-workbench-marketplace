#!/usr/bin/env bash
# in_root.sh <script> <arguments...>: run the script with bash from inside its <repo-root>, the first argument that is
# an absolute path to a folder (tests/lib.sh explains why). With no such argument, from the current folder.
set -euo pipefail
script=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
shift
for argument in "$@"; do
  if [[ "$argument" == /* && -d "$argument" ]]; then cd "$argument"; break; fi
done
exec bash "$script" "$@"
