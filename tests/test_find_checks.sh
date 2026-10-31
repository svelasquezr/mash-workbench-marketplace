# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
find_checks="$PWD/plugins/review-routing/skills/review-changes/find-checks.sh"
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
fresh() { local d="$temporary_directory/$1"; mkdir -p "$d"; printf '%s' "$d"; }

# Usage: one existing directory.
run_capturing bash "$find_checks"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$find_checks" "$temporary_directory/missing"
assert_eq "$captured_exit_code" "2"

# Nothing configured: no output, exit 0.
empty=$(fresh empty)
run_capturing bash "$find_checks" "$empty"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""

# package.json: scripts named test, lint, format, typecheck or check; others are ignored.
node=$(fresh node)
cat > "$node/package.json" <<'JSON'
{"scripts": {"test": "jest", "lint": "eslint .", "build": "tsc", "typecheck": "tsc --noEmit", "start": "node ."}}
JSON
run_capturing bash "$find_checks" "$node"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "$(printf 'npm test\tpackage.json')"
assert_contains "$captured_output" "$(printf 'npm run lint\tpackage.json')"
assert_contains "$captured_output" "$(printf 'npm run typecheck\tpackage.json')"
assert_not_contains "$captured_output" "build"
assert_not_contains "$captured_output" "start"

# A package.json that is not JSON never fails the script.
broken=$(fresh broken)
printf 'not json' > "$broken/package.json"
run_capturing bash "$find_checks" "$broken"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" ""

# Makefile and justfile targets.
make_dir=$(fresh make)
printf 'build:\n\techo b\n\ntest:\n\tpytest\n\nlint: deps\n\truff check .\n' > "$make_dir/Makefile"
printf 'default:\n  echo hi\n\ncheck:\n  cargo check\n' > "$make_dir/justfile"
run_capturing bash "$find_checks" "$make_dir"
assert_contains "$captured_output" "$(printf 'make test\tMakefile')"
assert_contains "$captured_output" "$(printf 'make lint\tMakefile')"
assert_not_contains "$captured_output" "make build"
assert_contains "$captured_output" "$(printf 'just check\tjustfile')"
assert_not_contains "$captured_output" "just default"

# pyproject.toml tool sections and pre-commit.
py=$(fresh py)
printf '[tool.pytest.ini_options]\nx = 1\n\n[tool.ruff]\nline-length = 100\n\n[tool.mypy]\nstrict = true\n' > "$py/pyproject.toml"
printf 'repos: []\n' > "$py/.pre-commit-config.yaml"
run_capturing bash "$find_checks" "$py"
assert_contains "$captured_output" "$(printf 'pytest\tpyproject.toml')"
assert_contains "$captured_output" "$(printf 'ruff check .\tpyproject.toml')"
assert_contains "$captured_output" "$(printf 'mypy .\tpyproject.toml')"
assert_contains "$captured_output" "$(printf 'pre-commit run --all-files\t.pre-commit-config.yaml')"

# CI files: GitHub Actions run: lines and GitLab script: items that look like checks; installs are skipped.
ci=$(fresh ci)
mkdir -p "$ci/.github/workflows"
cat > "$ci/.github/workflows/ci.yml" <<'YAML'
jobs:
  test:
    steps:
      - run: npm ci
      - run: npm run test -- --coverage
      - run: go vet ./...
      - name: Lint
        run: golangci-lint run
YAML
cat > "$ci/.gitlab-ci.yml" <<'YAML'
test:
  script:
    - pip install -r requirements.txt
    - pytest -q
YAML
run_capturing bash "$find_checks" "$ci"
assert_contains "$captured_output" "$(printf 'npm run test -- --coverage\t.github/workflows/ci.yml')"
assert_contains "$captured_output" "$(printf 'golangci-lint run\t.github/workflows/ci.yml')"
assert_contains "$captured_output" "$(printf 'pytest -q\t.gitlab-ci.yml')"
assert_not_contains "$captured_output" "npm ci"
assert_not_contains "$captured_output" "pip install"

# The same command from two files is listed once per file, never twice for one file; the script never runs anything.
dup=$(fresh dup)
printf 'test:\n\techo ran > ran.txt\n' > "$dup/Makefile"
run_capturing bash "$find_checks" "$dup"
run_capturing bash "$find_checks" "$dup"
assert_eq "$(printf '%s\n' "$captured_output" | grep -c 'make test')" "1"
[[ ! -e "$dup/ran.txt" ]] || { echo "find-checks ran a command"; exit 1; }

# A CI file whose last command is not a check still exits 0 (set -e must not leak out of the && lists).
tail_ci=$(fresh tail_ci)
mkdir -p "$tail_ci/.github/workflows"
printf 'jobs:\n  a:\n    steps:\n      - run: pytest\n      - run: echo done\n' > "$tail_ci/.github/workflows/ci.yml"
run_capturing bash "$find_checks" "$tail_ci"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "pytest"

# Best-effort parsing: CRLF and trailing comments are stripped; a justfile variable is not a recipe.
messy=$(fresh messy)
mkdir -p "$messy/.github/workflows"
printf 'jobs:\r\n  a:\r\n    steps:\r\n      - run: pytest -q  # unit tests\r\n' > "$messy/.github/workflows/ci.yml"
printf 'test := "x"\ncheck:\n  true\n' > "$messy/justfile"
run_capturing bash "$find_checks" "$messy"
assert_contains "$captured_output" "$(printf 'pytest -q\t.github/workflows/ci.yml')"
assert_not_contains "$captured_output" "just test"
assert_contains "$captured_output" "just check"

# An unreadable CI file is skipped and the files after it are still read (not as root, which reads everything).
if [[ "$(id -u)" != 0 ]]; then
  unreadable=$(fresh unreadable)
  mkdir -p "$unreadable/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - run: pytest\n' > "$unreadable/.github/workflows/a.yml"
  printf 'jobs:\n  a:\n    steps:\n      - run: ruff check .\n' > "$unreadable/.github/workflows/b.yml"
  chmod 000 "$unreadable/.github/workflows/a.yml"
  run_capturing bash "$find_checks" "$unreadable"
  chmod 644 "$unreadable/.github/workflows/a.yml"
  assert_eq "$captured_exit_code" "0"
  assert_contains "$captured_output" "ruff check ."
fi

# The same command named in two files is listed once for each.
two=$(fresh two)
mkdir -p "$two/.github/workflows"
printf 'test:\n\tpytest\n' > "$two/Makefile"
printf 'jobs:\n  a:\n    steps:\n      - run: make test\n' > "$two/.github/workflows/ci.yml"
run_capturing bash "$find_checks" "$two"
assert_contains "$captured_output" "$(printf 'make test\tMakefile')"
assert_contains "$captured_output" "$(printf 'make test\t.github/workflows/ci.yml')"
