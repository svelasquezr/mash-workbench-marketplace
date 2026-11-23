#!/usr/bin/env bash
# Runs the mash-review eval cases (evals/mash-review/) with `claude plugin eval`.
# The eval tool reads cases only from inside the plugin folder, and a case folder there would ship to every user.
# So this script copies plugins/mash-review and the cases into a temporary folder, runs the eval on the copy, and copies
# the results back to evals/mash-review/results/ (ignored by git). Extra arguments go to `claude plugin eval`.
# Pros: the plugin ships no eval files. Cons: a run sees the plugin as it is on disk, not as committed.
set -euo pipefail
cd "$(dirname "$0")/.."
plugin=plugins/mash-review
cases=evals/mash-review
[[ -d "$plugin" && -d "$cases" ]] || { echo "eval-mash-review: run from a checkout that has $plugin and $cases" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$plugin" "$work/mash-review"
mkdir -p "$work/mash-review/evals"
for case_folder in "$cases"/*/; do
  [[ "$(basename "$case_folder")" == results ]] && continue
  cp -R "${case_folder%/}" "$work/mash-review/evals/"
done

status=0
claude plugin eval "$work/mash-review" --scaffold --runs 1 --ablation none --no-publish --trust-plugin --judge-model sonnet \
  --allow-tools Write Edit "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)" "Bash(git merge-base:*)" \
  "Bash(git rev-parse:*)" "Bash(git worktree list:*)" "Bash(git blame:*)" "Bash(git show:*)" "Bash(git branch:*)" \
  "Bash(bash check.sh)" "$@" || status=$?

if [[ -d "$work/mash-review/evals/results" ]]; then
  mkdir -p "$cases/results"
  cp -R "$work/mash-review/evals/results/." "$cases/results/"
  echo "results: $cases/results/"
fi
exit "$status"
