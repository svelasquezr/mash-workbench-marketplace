#!/usr/bin/env bash
# Is this copy of the plugin the one Claude Code has installed? The scripts that can get a Claude Code allow rule
# (escape-add.sh, review-log.sh, backlog-add.sh) run this first and stop when the answer is no.
# Why: an allow rule names one exact script path, and that path holds the plugin's version folder. After a plugin
# update, Claude Code keeps the old version's folder in its plugin cache, and a rule that the user accepted for the
# old version still approves the old scripts with no prompt, also when the new version fixed a security bug in them.
# So a copy that is not installed any more refuses to run.
#
# Usage: plugin-current.sh        (no arguments; it looks at the folder it is in)
#
# How it decides. Claude Code installs a plugin in <config>/plugins/cache/<marketplace>/<plugin>/<version>/ and lists
# each installed copy in <config>/plugins/installed_plugins.json, as an entry with an "installPath" and, for a plugin
# that is installed for one project only, a "projectPath". When this file is in a folder of that shape, and that
# registry is next to the cache folder, an entry must name this copy: its installPath ends with
# cache/<marketplace>/<plugin>/<version>, and it has no projectPath (installed for the user), or its projectPath is
# the current folder, the top folder of its git checkout when the current folder is really inside it, or the main
# worktree of that checkout's repository. An entry of another
# project does not count: a registry can list old versions for many old projects. Paths are compared without regard
# to case, with "\" as "/" and a drive letter "C:/" as "/c/", so a Windows spelling matches the Git Bash one.
# Otherwise this copy is an old one: exit 6.
# It cannot answer, and lets the copy run (exit 0), when the plugin is not in a cache folder (a clone, or
# claude --plugin-dir), when there is no registry next to the cache, or when the registry holds no complete entry
# with an "installPath" (another format, an empty file, a file cut in the middle of a write). In the last two cases
# the copy is in a cache-shaped folder, so the script prints one line on stderr: this check is a second guard, and a
# reader must see when it did not work. The same file ships in each MASH plugin (tests/test_plugin_current.sh compares the copies).
# Reads only that registry file, and asks git for the main worktree of the current folder. Writes nothing. No network.
# Exit codes: 0 this copy may run; 6 this copy is in the plugin cache and is not installed for this folder.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
version_folder=$(dirname "$here")
plugin_folder=$(dirname "$version_folder")
marketplace_folder=$(dirname "$plugin_folder")
cache_folder=$(dirname "$marketplace_folder")
[[ "$(basename "$cache_folder")" == cache ]] || exit 0
registry="$(dirname "$cache_folder")/installed_plugins.json"
version=$(basename "$version_folder")
plugin=$(basename "$plugin_folder")
cannot_tell() {
  echo "plugin-current: cannot tell if $plugin $version in $version_folder is the installed version ($1); the copy runs" >&2
  exit 0
}
[[ -f "$registry" && -r "$registry" ]] || cannot_tell "no installed_plugins.json next to the cache folder"
tail="/cache/$(basename "$marketplace_folder")/$plugin/$version"
# clean: stdin paths to stdout in one spelling: JSON's \\ and \/ as /, a drive letter as /c/, lowercase, no trailing /.
clean() { sed -e 's|\\\\|/|g' -e 's|\\/|/|g' -e 's|\\|/|g' -e 's|^\([A-Za-z]\):/|/\1/|' -e 's|//*|/|g' -e 's|\(.\)/$|\1|' | tr '[:upper:]' '[:lower:]'; }
# The entries, one per line: "<installPath><TAB><projectPath, or empty>". The file is read as tokens (strings and the
# characters {}[]:, and null, true, false and numbers as values), so line breaks and the order of the keys do not matter.
# An entry is one JSON object: the installPath and the projectPath that are direct members of the same object.
entries=$({ tr -d '\r' < "$registry" | grep -oE '"([^"\\]|\\.)*"|[][{}:]|null|true|false|-?[0-9][0-9.eE+-]*' || true; } | awk '
  $0 == "{" { depth++; install[depth] = ""; project[depth] = ""; key = ""; next }
  $0 == "}" { if (depth > 0) { if (install[depth] != "") print install[depth] "\t" project[depth]; depth-- } key = ""; next }
  $0 == ":" { key = last; next }
  /^"/ {
    value = substr($0, 2, length($0) - 2)
    if (key == "installPath") install[depth] = value
    else if (key == "projectPath") project[depth] = value
    last = value; key = ""
    next
  }
  { key = "" }')
[[ -n "$entries" ]] || cannot_tell "installed_plugins.json holds no entry with an installPath"
# The folders that count as "this project": the current folder (as written and resolved), the top folder of its git
# checkout, and the main worktree of its repository. Not every folder above: an old entry for the home folder would
# then count for every project under it.
# git answers from its config, and a folder can be shaped like a git directory whose core.worktree names another
# project. So git's top folder counts only when the current folder is really inside it, and the main worktree only then.
here_folders=$(
  real_here=$(pwd -P)
  printf '%s\n%s\n' "$PWD" "$real_here"
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  top=${top%$'\r'}
  if [[ -n "$top" ]]; then top=$(cd "$top" 2>/dev/null && pwd -P) || top=""; fi
  if [[ -n "$top" && ( "$real_here" == "$top" || "$real_here" == "${top%/}"/* ) ]]; then
    printf '%s\n' "$top"
    common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    common=${common%$'\r'}
    if [[ -n "$common" && "$(basename "$common")" == .git ]]; then (cd "$(dirname "$common")" 2>/dev/null && pwd -P) || true; fi
  fi
)
here_folders=$(printf '%s\n' "$here_folders" | clean)
wanted=$(printf '%s\n' "$tail" | clean)
tab=$'\t'
while IFS= read -r entry; do
  install=$(printf '%s\n' "${entry%%"$tab"*}" | clean)
  project=${entry#*"$tab"}
  [[ "$install" == *"$wanted" ]] || continue
  if [[ -z "$project" ]]; then exit 0; fi
  project=$(printf '%s\n' "$project" | clean)
  if grep -Fxq -- "$project" <<< "$here_folders"; then exit 0; fi
done <<< "$entries"
{
  echo "plugin-current: this is $plugin $version in Claude Code's plugin cache, and it is not the installed version for this folder: an update left this copy behind."
  echo "Nothing ran. Use the installed version's scripts (start a new session after a plugin update), and remove the allow rules that name this folder: $version_folder"
} >&2
exit 6
