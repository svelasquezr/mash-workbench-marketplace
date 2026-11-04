# shellcheck shell=bash
# review-changes' "Routing with git" and "The diff file": every command the reference prescribes is pinned here by
# its exact text (so editing the reference without this test fails), then run on a fixture repository with a branch
# and a base that moved on, checking each near miss the recipe must get right.
set -euo pipefail
source tests/lib.sh
reference=$(cat plugins/review-routing/skills/review-changes/reference.md)
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT

# The documented commands, verbatim.
# shellcheck disable=SC2016  # literal Markdown
for documented in \
  'git diff --name-only --no-renames <R>' \
  'git --glob-pathspecs diff --name-only --no-renames <R> -- <paths>' \
  "git --glob-pathspecs diff --name-only --no-renames <R> -- . ':!<p>'" \
  "git --glob-pathspecs diff --name-only --no-renames -G'<line_regex>' <R> -- <paths>" \
  'with `-i` before `-G` when `ignore_case = true`' \
  "git log --format=%s --right-only <R> | grep -E -c '<commit_regex>'" \
  'git --glob-pathspecs diff --shortstat --no-renames <R> -- <paths>' \
  '`N insertion(+)` or `N insertions(+)`' \
  "git log --format='%h %s' --right-only <R>" \
  'git diff --no-renames -W <R>' \
  "git rev-parse --verify '<name>^{commit}'"; do
  assert_contains "$reference" "$documented"
done

# Fixture: main, a feature branch, and a main that moved on after the branch point.
repository="$temporary_directory/consumer"
mkdir -p "$repository" && cd "$repository"
git init -q -b main && git config user.email t@example.com && git config user.name t
mkdir -p src/payments src/app tests/payments docs/archive nested
for file in src/payments/charge.py src/app/payments_page.py tests/payments/test_charge.py docs/guide.md \
  docs/archive/old.md docs/archive/claimed.md README.md nested/README.md; do echo "v1" > "$file"; done
printf '{\n  "dependencies": {}\n}\n' > package.json
git add -A && git commit -qm "chore: init"
git checkout -qb feature
printf 'v1\nv2\n' > src/payments/charge.py && git commit -qam "feat: charge twice"
printf '{\n  "dependencies": {"Payments-SDK": "2"}\n}\n' > package.json
for file in src/app/payments_page.py docs/archive/old.md docs/archive/claimed.md README.md nested/README.md; do
  echo "v2" > "$file"
done
git commit -qam "chore: bump the sdk and touch docs"
git checkout -q main && echo "v2" > docs/guide.md && git commit -qam "feat: main moved on" && git checkout -q feature
base=$(git rev-parse --verify 'main^{commit}'); head=$(git rev-parse --verify 'feature^{commit}')
R="$base...$head"
lines() { tr '\n' ' ' | sed 's/ $//'; }

# Step 3: the change's own paths only (main's docs/guide.md is not in it).
assert_eq "$(git diff --name-only --no-renames "$R" | lines)" \
  "README.md docs/archive/claimed.md docs/archive/old.md nested/README.md package.json src/app/payments_page.py src/payments/charge.py"
# Step 4: a folder claims its subtree, not a look-alike; *.md is top level only; :! leaves a folder out.
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames "$R" -- 'src/payments' 'tests/payments' | lines)" "src/payments/charge.py"
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames "$R" -- 'docs' '*.md' ':!docs/archive' | lines)" "README.md"
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames "$R" -- 'docs/archive/claimed.md' | lines)" "docs/archive/claimed.md"
# Step 5: the first pass negates every route's positives; the second pass adds what a route excluded and no route claimed.
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames "$R" -- . ':!src/payments' ':!tests/payments' ':!docs' ':!*.md' ':!docs/archive/claimed.md' | lines)" \
  "nested/README.md package.json src/app/payments_page.py"
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames "$R" -- 'docs/archive' | lines)" "docs/archive/claimed.md docs/archive/old.md"
# Step 6: -G is case-sensitive unless -i comes first.
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames -G'payments-sdk' "$R" -- 'package.json' | lines)" ""
assert_eq "$(git --glob-pathspecs diff --name-only --no-renames -i -G'payments-sdk' "$R" -- 'package.json' | lines)" "package.json"
# Step 7: subjects of the branch only (main's "feat: main moved on" is left out), and the singular insertion.
assert_eq "$(git log --format=%s --right-only "$R" | grep -E -c '^feat')" "1"
assert_contains "$(git --glob-pathspecs diff --shortstat --no-renames "$R" -- 'src/payments')" "1 insertion(+)"
# The diff file's commit list is the branch's own.
assert_eq "$(git log --format='%h %s' --right-only "$R" | wc -l | tr -d ' ')" "2"
# A fix round's two-dot range works with --right-only too.
assert_eq "$(git log --format=%s --right-only "$base..$head" | grep -E -c '^chore')" "1"
