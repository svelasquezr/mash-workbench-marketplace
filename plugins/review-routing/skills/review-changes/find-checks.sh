#!/usr/bin/env bash
# List the commands a repository seems to use as automated checks (tests, lint, format, types), one per line:
# "<command><TAB><file it came from>". It only reads files and never runs anything: the review-changes skill
# shows the list to the user, who confirms before any command runs. Prints nothing and exits 0 when it finds
# nothing; best-effort, so an unreadable or malformed file is skipped. Exit 2 on a usage error.
#   Read: package.json scripts, Makefile/justfile targets, pyproject.toml tool sections,
#   .pre-commit-config.yaml, and check-like lines of CI files (.github/workflows, .gitlab-ci.yml).
#   Not read: a target with several names (`test lint:`), recipe parameters, a leading `@`, `${{ }}` expressions.
set -euo pipefail
usage="usage: find-checks.sh <repo-root>"
[[ $# -eq 1 && -d "$1" ]] || { echo "$usage" >&2; exit 2; }
root="$(cd "$1" && pwd -P)"
names='test|lint|format|typecheck|check'
emit() { printf '%s\t%s\n' "$1" "$2"; }

if [[ -f "$root/package.json" ]]; then
  python3 -I - "$root/package.json" <<'PY' || true
import json, sys
try:
    scripts = json.load(open(sys.argv[1])).get("scripts", {})
    for name in ("test", "lint", "format", "typecheck", "check"):
        if isinstance(scripts, dict) and name in scripts:
            print(("npm test" if name == "test" else f"npm run {name}") + "\tpackage.json")
except Exception:
    pass
PY
fi

for build_file in Makefile makefile GNUmakefile; do
  [[ -f "$root/$build_file" ]] || continue
  for target in $(grep -E "^($names)[[:space:]]*:([^=]|$)" "$root/$build_file" 2>/dev/null | grep -oE "^($names)" | sort -u || true); do
    emit "make $target" "$build_file"
  done
  break
done
for just_file in justfile Justfile; do
  [[ -f "$root/$just_file" ]] || continue
  for recipe in $(grep -E "^($names)[[:space:]]*:([^=]|$)" "$root/$just_file" 2>/dev/null | grep -oE "^($names)" | sort -u || true); do
    emit "just $recipe" "$just_file"
  done
  break
done

if [[ -f "$root/pyproject.toml" ]]; then
  grep -q '^\[tool\.pytest' "$root/pyproject.toml" 2>/dev/null && emit "pytest" "pyproject.toml"
  grep -q '^\[tool\.ruff' "$root/pyproject.toml" 2>/dev/null && emit "ruff check ." "pyproject.toml"
  grep -q '^\[tool\.mypy' "$root/pyproject.toml" 2>/dev/null && emit "mypy ." "pyproject.toml"
fi
[[ -f "$root/.pre-commit-config.yaml" ]] && emit "pre-commit run --all-files" ".pre-commit-config.yaml"

# CI files: single-line `run:` (GitHub Actions) and `- <command>` items under `script:` (GitLab) that look like checks.
looks_like_check='(^|[^[:alnum:]_-])(test|tests|lint|format|typecheck|check|mypy|ruff|pytest|eslint|tsc|vet|golangci-lint|clippy|rubocop)([^[:alnum:]_-]|$)'
ci_commands() {
  local file="$1" in_script=0 line command
  [[ -r "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    command=""
    if [[ "$line" =~ ^[[:space:]-]*run:[[:space:]]+(.+)$ ]]; then
      command="${BASH_REMATCH[1]}"; in_script=0
    elif [[ "$line" =~ ^[[:space:]]*(before_|after_)?script:[[:space:]]*$ ]]; then
      in_script=1; continue
    elif (( in_script )) && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
      command="${BASH_REMATCH[1]}"
    elif (( in_script )); then
      in_script=0
    fi
    [[ -n "$command" ]] || continue
    [[ "$command" != "|"* && "$command" != ">"* ]] || continue
    case "$command" in
      \"*\") command="${command#\"}"; command="${command%\"}" ;;
      \'*\') command="${command#\'}"; command="${command%\'}" ;;
      *) command="$(printf '%s' "$command" | sed -E 's/[[:space:]]+#.*$//')" ;;
    esac
    [[ "$command" =~ (^|[[:space:]])(npm\ ci|(pip3?|npm|yarn|pnpm|apt|apt-get|brew|gem|bundle|poetry|uv|uv\ pip)\ install|apt-get\ update)([[:space:]]|$) ]] && continue
    [[ "$command" =~ (actions/checkout|setup-) ]] && continue
    if [[ "$command" =~ $looks_like_check ]]; then emit "$command" "${file#"$root"/}"; fi
  done < "$file"
  return 0
}
for ci_file in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml "$root/.gitlab-ci.yml"; do
  if [[ -f "$ci_file" ]]; then ci_commands "$ci_file" | awk '!seen[$0]++'; fi
done
exit 0
