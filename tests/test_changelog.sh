# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh

# Each plugin has a CHANGELOG.md with a heading "## <version> - <date>" for the version in its plugin.json.
for manifest in plugins/*/.claude-plugin/plugin.json; do
  plugin_directory=${manifest%/.claude-plugin/plugin.json}
  version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
  [[ -n "$version" ]] || { echo "  no version in $manifest"; exit 1; }
  assert_file "$plugin_directory/CHANGELOG.md"
  heading_count=0
  while IFS= read -r line; do
    line=${line%$'\r'}
    case "$line" in "## $version - "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) heading_count=$((heading_count + 1)) ;; esac
  done < "$plugin_directory/CHANGELOG.md"
  assert_eq "$heading_count" "1"
done
