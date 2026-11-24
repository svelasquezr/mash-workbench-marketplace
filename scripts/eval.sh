#!/usr/bin/env bash
# Usage: bash scripts/eval.sh <plugin> [claude plugin eval options]
# Runs the eval cases of one plugin (evals/<plugin>/) with `claude plugin eval`.
# The eval tool reads cases only from inside the plugin folder, and a case folder there would ship to every user.
# So this script copies plugins/<plugin> and the cases into a temporary folder, runs the eval on the copy, and copies
# the results back to evals/<plugin>/results/ (ignored by git). Extra arguments go to `claude plugin eval`.
# Pros: the plugin ships no eval files. Cons: a run sees the plugin as it is on disk, not as committed.
set -euo pipefail
cd "$(dirname "$0")/.."
usage="usage: bash scripts/eval.sh <plugin> [claude plugin eval options], where <plugin> is a folder name in plugins/"
name=${1-}
# A plain folder name only: no path, no option, nothing that leaves plugins/ or evals/.
[[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "$usage" >&2; exit 2; }
shift
plugin=plugins/$name
cases=evals/$name
[[ -d "$plugin" && -d "$cases" ]] || { echo "eval: run from a checkout that has $plugin and $cases" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$plugin" "$work/$name"
mkdir -p "$work/$name/evals"
for case_folder in "$cases"/*/; do
  [[ "$(basename "$case_folder")" == results ]] && continue
  cp -R "${case_folder%/}" "$work/$name/evals/"
done

status=0
claude plugin eval "$work/$name" --scaffold --runs 1 --ablation none --no-publish --trust-plugin --judge-model sonnet \
  --allow-tools Write Edit "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)" "Bash(git merge-base:*)" \
  "Bash(git rev-parse:*)" "Bash(git worktree list:*)" "Bash(git blame:*)" "Bash(git show:*)" "Bash(git branch:*)" \
  "Bash(bash check.sh)" "$@" || status=$?

if [[ -d "$work/$name/evals/results" ]]; then
  mkdir -p "$cases/results"
  cp -R "$work/$name/evals/results/." "$cases/results/"
  echo "results: $cases/results/"
fi
exit "$status"
