#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/run.sh
for manifest in .claude-plugin/marketplace.json .github/plugin/marketplace.json plugins/*/.claude-plugin/plugin.json; do python3 -m json.tool "$manifest" >/dev/null; done
if command -v claude >/dev/null; then
  claude plugin validate --strict .
  for plugin_directory in plugins/*/; do claude plugin validate --strict "$plugin_directory"; done
elif [[ -n "${CI:-}" ]]; then
  echo "claude CLI is required in CI for 'claude plugin validate'" >&2
  exit 1
else
  echo "claude not installed: skipped 'claude plugin validate'"
fi
