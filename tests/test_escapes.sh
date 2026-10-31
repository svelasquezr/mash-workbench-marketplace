# shellcheck shell=bash
set -euo pipefail
source tests/lib.sh
add=plugins/review-routing/skills/add-reviewer/escape-add.sh
report=plugins/review-routing/skills/add-reviewer/escapes-report.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
ledger="$temporary_directory/docs/review-escapes.md"
# These tests name the ledger file; tests/test_ledger_location.sh covers choosing and finding it.
export REVIEW_ROUTING_ESCAPES=docs/review-escapes.md

# No ledger yet: the report says so and exits 0.
run_capturing bash "$report" "$temporary_directory"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no escapes recorded"

# Recording creates the ledger with a header, one line per bug, keyed by its issue link.
output=$(ESCAPE_DATE=2026-10-11 bash "$add" "$temporary_directory" src/payments missing-test "https://example.test/pull/12")
assert_contains "$output" "recorded"
assert_contains "$(cat "$ledger")" "# Review escapes"
assert_contains "$(cat "$ledger")" "- 2026-10-11 · src/payments · missing-test · https://example.test/pull/12"
ESCAPE_DATE=2026-10-12 bash "$add" "$temporary_directory" src/payments/ wrong-claim "https://example.test/pull/14" >/dev/null
ESCAPE_DATE=2026-10-12 bash "$add" "$temporary_directory" docs stale-doc "https://example.test/pull/15" >/dev/null
assert_eq "$(grep -c '^- ' "$ledger")" "3"

# The report counts by area (a trailing slash is the same area) and names the area that reached the threshold.
run_capturing bash "$report" "$temporary_directory"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "src/payments: 2 escapes (missing-test 1, wrong-claim 1)"
assert_contains "$captured_output" "add a reviewer for src/payments"
assert_contains "$captured_output" "docs: 1 escape (stale-doc 1)"
assert_not_contains "$captured_output" "add a reviewer for docs"
run_capturing bash "$report" "$temporary_directory" --threshold 1
assert_contains "$captured_output" "add a reviewer for docs"

# Usage errors: a missing field, an unknown option.
run_capturing bash "$add" "$temporary_directory" src/payments "" "https://example.test/pull/16"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$report" "$temporary_directory" --threshold zero
assert_eq "$captured_exit_code" "2"

# Review follow-ups. A ledger with only its header has no escapes.
header_only="$temporary_directory/header-only"; mkdir -p "$header_only/docs"
printf '# Review escapes\n\nBugs found after the reviewers said SAFE TO LAND.\n- a note in prose, not an entry\n' > "$header_only/docs/review-escapes.md"
run_capturing bash "$report" "$header_only"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no escapes recorded"

# Most escapes first, whatever order they were recorded in; a leading ./ and trailing / name the same area.
ordered="$temporary_directory/ordered"; mkdir -p "$ordered/src/payments"
bash "$add" "$ordered" docs stale-doc "https://example.test/pull/1" >/dev/null
bash "$add" "$ordered" ./src/payments/ missing-test "https://example.test/pull/2" >/dev/null
bash "$add" "$ordered" src/payments wrong-claim "https://example.test/pull/3" >/dev/null
run_capturing bash "$report" "$ordered"
assert_eq "$(printf '%s\n' "$captured_output" | head -1)" "src/payments: 2 escapes (missing-test 1, wrong-claim 1) -> add a reviewer for src/payments (add-reviewer skill)"

# The area is a directory, never a file; the separator character is refused in any field.
printf 'x\n' > "$ordered/src/payments/refund.py"
run_capturing bash "$add" "$ordered" src/payments/refund.py missing-test "https://example.test/pull/4"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "a directory"
run_capturing bash "$add" "$ordered" src/payments "miss · ing" "https://example.test/pull/5"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$add" "$ordered" / missing-test "https://example.test/pull/6"
assert_eq "$captured_exit_code" "2"

# A bare --threshold and a missing root are usage errors.
run_capturing bash "$report" "$ordered" --threshold
assert_eq "$captured_exit_code" "2"
run_capturing bash "$report" "$temporary_directory/does-not-exist"
assert_eq "$captured_exit_code" "2"

# Areas are normalised: repeated trailing slashes go; absolute, parent and dot areas are refused, and so
# is a line break in any field.
normal="$temporary_directory/normal"; mkdir -p "$normal"
bash "$add" "$normal" src/payments// missing-test "https://example.test/pull/7" >/dev/null
assert_contains "$(cat "$normal/docs/review-escapes.md")" "· src/payments · missing-test ·"
for bad_area in /abs ../x . ./; do
  run_capturing bash "$add" "$normal" "$bad_area" missing-test "https://example.test/pull/8"
  assert_eq "$captured_exit_code" "2"
done
run_capturing bash "$add" "$normal" src/payments $'two\nlines' "https://example.test/pull/9"
assert_eq "$captured_exit_code" "2"
# A hand-edited entry with ./ or a trailing slash counts as the same area.
printf -- '- 2026-10-11 · ./src/payments/ · stale-doc · https://example.test/pull/10\n' >> "$normal/docs/review-escapes.md"
run_capturing bash "$report" "$normal"
assert_contains "$captured_output" "src/payments: 2 escapes"

# One line per bug, keyed by its issue: the same link twice leaves one entry, exit 0, "already recorded".
keyed="$temporary_directory/keyed"; mkdir -p "$keyed"
bash "$add" "$keyed" src/store wrong-result "https://example.test/issues/52" >/dev/null
run_capturing bash "$add" "$keyed" src/store wrong-result "https://example.test/issues/52"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "already recorded"
run_capturing bash "$add" "$keyed" src/other other-class "https://example.test/issues/52"
assert_contains "$captured_output" "already recorded"
assert_eq "$(grep -c '^- ' "$keyed/docs/review-escapes.md")" "1"
# A link that only contains a recorded one is a different bug.
bash "$add" "$keyed" src/other other-class "https://example.test/issues/520" >/dev/null
assert_eq "$(grep -c '^- ' "$keyed/docs/review-escapes.md")" "2"

# The entry below the threshold prints no report line; the one that reaches it prints that area's line.
threshold="$temporary_directory/threshold"; mkdir -p "$threshold"
run_capturing bash "$add" "$threshold" libs/store wrong-result "https://example.test/issues/1"
assert_not_contains "$captured_output" "add a reviewer"
run_capturing bash "$add" "$threshold" libs/other wrong-result "https://example.test/issues/2"
assert_not_contains "$captured_output" "add a reviewer"
run_capturing bash "$add" "$threshold" libs/store/ data-loss "https://example.test/issues/3"
assert_contains "$captured_output" "libs/store: 2 escapes (wrong-result 1, data-loss 1) -> add a reviewer for libs/store (add-reviewer skill)"
assert_not_contains "$captured_output" "libs/other"
# Re-running the entry that reached it adds nothing and prints no report line.
run_capturing bash "$add" "$threshold" libs/store data-loss "https://example.test/issues/3"
assert_not_contains "$captured_output" "add a reviewer"
assert_eq "$(grep -c '^- ' "$threshold/docs/review-escapes.md")" "3"

# The definition and the escape: field are written everywhere they matter.
for file in plugins/review-routing/agents/change-reviewer.md plugins/review-routing/skills/add-reviewer/reviewer-template.md; do
  assert_contains "$(cat "$file")" "escape: yes"
  assert_contains "$(cat "$file")" "escape: no"
done
assert_contains "$(cat plugins/review-routing/skills/add-reviewer/SKILL.md)" "one line per bug, keyed by its issue"
assert_contains "$(cat plugins/review-routing/skills/review-changes/reference.md)" "-> add a reviewer for"
assert_contains "$(cat plugins/review-routing/skills/review-changes/SKILL.md)" "issue link"
assert_not_contains "$(cat plugins/review-routing/skills/add-reviewer/escape-add.sh)" "repeats count"

# Links are normalised before the duplicate check and the write: every spelling of one GitHub issue is one entry.
norm="$temporary_directory/norm"; mkdir -p "$norm"
git -C "$norm" init -q
git -C "$norm" remote add origin git@github.com:o/jba.git
bash "$add" "$norm" libs/store wrong-result "https://github.com/o/jba/issues/52" >/dev/null
for spelling in "#52" "o/jba#52" "https://github.com/o/jba/issues/52/" "https://github.com/o/jba/pull/52" "https://github.com/o/jba/pull/52/"; do
  run_capturing bash "$add" "$norm" libs/store wrong-result "$spelling"
  assert_eq "$captured_exit_code" "0"
  assert_contains "$captured_output" "already recorded"
done
assert_eq "$(grep -c '^- ' "$norm/docs/review-escapes.md")" "1"
# A new spelling is written in the canonical form; other links lose only a trailing slash.
bash "$add" "$norm" libs/store wrong-result "#53" >/dev/null
assert_contains "$(cat "$norm/docs/review-escapes.md")" "· https://github.com/o/jba/issues/53"
bash "$add" "$norm" libs/other wrong-result "https://example.test/issues/9/" >/dev/null
assert_eq "$(grep -c "issues/9$" "$norm/docs/review-escapes.md")" "1"
# The https origin form resolves too.
norm_https="$temporary_directory/norm-https"; mkdir -p "$norm_https"
git -C "$norm_https" init -q
git -C "$norm_https" remote add origin https://github.com/o/jba
bash "$add" "$norm_https" libs/store wrong-result "#7" >/dev/null
assert_contains "$(cat "$norm_https/docs/review-escapes.md")" "· https://github.com/o/jba/issues/7"
# #N with no GitHub origin is refused and the ledger is left alone.
no_origin="$temporary_directory/no-origin"; mkdir -p "$no_origin"
git -C "$no_origin" init -q
run_capturing bash "$add" "$no_origin" libs/store wrong-result "#52"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "origin"
assert_eq "$([[ -e "$no_origin/docs/review-escapes.md" ]] && echo exists || echo none)" "none"

# The report counts distinct links per area, so a duplicated line does not inflate a count.
dup="$temporary_directory/dup"; mkdir -p "$dup/docs"
printf -- '- 2026-10-11 · libs/store · a · https://example.test/issues/1\n- 2026-10-12 · libs/store · a · https://example.test/issues/1\n' > "$dup/docs/review-escapes.md"
run_capturing bash "$report" "$dup"
assert_contains "$captured_output" "libs/store: 1 escape (a 1)"
assert_not_contains "$captured_output" "add a reviewer"

# The threshold has no environment override.
assert_not_contains "$(cat plugins/review-routing/skills/add-reviewer/escape-add.sh)" "ESCAPE_THRESHOLD"
# escape: yes is limited to code an earlier review passed.
for file in plugins/review-routing/agents/change-reviewer.md plugins/review-routing/skills/add-reviewer/reviewer-template.md; do
  assert_contains "$(cat "$file")" "an earlier review passed"
  assert_contains "$(cat "$file")" "predates any review"
done

# Normalisation also lowercases owner and repo and drops www., a #fragment and a ?query from GitHub URLs.
case_dir="$temporary_directory/case"; mkdir -p "$case_dir"
git -C "$case_dir" init -q
git -C "$case_dir" remote add origin git@github.com:Owner/JBA.git
bash "$add" "$case_dir" libs/store wrong-result "#5" >/dev/null
assert_contains "$(cat "$case_dir/docs/review-escapes.md")" "· https://github.com/owner/jba/issues/5"
for spelling in "https://www.github.com/Owner/Jba/issues/5#issuecomment-1" "https://github.com/owner/jba/pull/5?notification_referrer_id=x" "Owner/JBA#5" "HTTPS://GitHub.com/Owner/JBA/issues/5"; do
  run_capturing bash "$add" "$case_dir" libs/store wrong-result "$spelling"
  assert_contains "$captured_output" "already recorded"
done
assert_eq "$(grep -c '^- ' "$case_dir/docs/review-escapes.md")" "1"
# Bash 3.2 (macOS) has no ${var,,} lowercasing: the scripts lowercase with tr.
if grep -q ',,}' "$add" "$report"; then echo "FAIL: bash-4-only \${var,,} in the escape scripts" >&2; exit 1; fi

# --- hostile or awkward input must not corrupt the ledger --------------------------------------------------------
fresh_ledger_dir() { local d; d=$(mktemp -d "$temporary_directory/h.XXXXXX"); mkdir -p "$d/docs"; printf '%s' "$d"; }
escape_ledger() { cat "$1/docs/review-escapes.md"; }

# A CRLF ledger without a final newline: known links are still recognised, a new entry starts on its own line, and the
# report counts two bugs, not three.
hostile=$(fresh_ledger_dir)
printf '# Review escapes\r\n- 2026-01-01 · src/a · wrong-result · https://github.com/o/r/issues/1\r\n- 2026-01-01 · src/a · wrong-result · https://github.com/o/r/issues/2' > "$hostile/docs/review-escapes.md"
run_capturing bash "$add" "$hostile" src/a wrong-result https://github.com/o/r/issues/1
assert_contains "$captured_output" "already recorded"
run_capturing bash "$add" "$hostile" src/a wrong-result https://github.com/o/r/issues/2
assert_contains "$captured_output" "already recorded"
assert_eq "$(bash "$report" "$hostile" | head -1)" "src/a: 2 escapes (wrong-result 2) -> add a reviewer for src/a (add-reviewer skill)"
bash "$add" "$hostile" src/b wrong-result https://github.com/o/r/issues/3 >/dev/null
assert_eq "$(grep -c '^- 20' "$hostile/docs/review-escapes.md")" "3"

# The date override must be a date; a carriage return in a field is refused like a newline.
hostile=$(fresh_ledger_dir)
run_capturing env ESCAPE_DATE='x; rm -rf /' bash "$add" "$hostile" src/a wrong-result "#5"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$add" "$hostile" $'src/a\r' wrong-result https://github.com/o/r/issues/5
assert_eq "$captured_exit_code" "2"

# Area: doubled slashes collapse, whitespace and tabs are refused.
hostile=$(fresh_ledger_dir)
bash "$add" "$hostile" src//payments wrong-result https://github.com/o/r/issues/6 >/dev/null
assert_contains "$(escape_ledger "$hostile")" "· src/payments · wrong-result ·"
run_capturing bash "$add" "$hostile" $'src/pay\tments' wrong-result https://github.com/o/r/issues/7
assert_eq "$captured_exit_code" "2"
run_capturing bash "$add" "$hostile" "src/payments " wrong-result https://github.com/o/r/issues/7
assert_eq "$captured_exit_code" "2"

# Class: lowercase words joined by hyphens, as the skill documents; no markup, mentions or spaces.
run_capturing bash "$add" "$hostile" src/payments 'oops @octocat [x](http://evil)' https://github.com/o/r/issues/8
assert_eq "$captured_exit_code" "2"
run_capturing bash "$add" "$hostile" src/payments Wrong-Result https://github.com/o/r/issues/8
assert_eq "$captured_exit_code" "2"

# A link that is not a web link is refused; any other http(s) link is kept as given.
for bad_link in 'javascript:alert(1)' '/etc/passwd' 'not a link at all'; do
  run_capturing bash "$add" "$hostile" src/payments wrong-result "$bad_link"
  assert_eq "$captured_exit_code" "2"
done
bash "$add" "$hostile" src/payments wrong-result https://tracker.example/bugs/42 >/dev/null
assert_contains "$(escape_ledger "$hostile")" "· https://tracker.example/bugs/42"

# #N resolves through the origin remote even when the URL carries credentials or a trailing slash.
for origin_url in 'https://user:TOKEN@github.com/O/R.git' 'git@github.com:O/R/' 'https://github.com/O/R/'; do
  hostile=$(fresh_ledger_dir); git -C "$hostile" init -q; git -C "$hostile" remote add origin "$origin_url"
  bash "$add" "$hostile" src/a wrong-result "#9" >/dev/null
  assert_contains "$(escape_ledger "$hostile")" "· https://github.com/o/r/issues/9"
  assert_not_contains "$(escape_ledger "$hostile")" "TOKEN"
done

# A backslash in the area is kept as typed, so the threshold line is still printed for it.
hostile=$(fresh_ledger_dir)
bash "$add" "$hostile" 'src/b\n' wrong-result https://github.com/o/r/issues/1 >/dev/null
run_capturing bash "$add" "$hostile" 'src/b\n' wrong-result https://github.com/o/r/issues/2
assert_contains "$captured_output" '-> add a reviewer for src/b\n'
# A pull request's files, commits or checks page is the same bug as the pull request.
hostile=$(fresh_ledger_dir)
bash "$add" "$hostile" src/a wrong-result https://github.com/o/r/pull/1 >/dev/null
run_capturing bash "$add" "$hostile" src/a wrong-result https://github.com/o/r/pull/1/files
assert_contains "$captured_output" "already recorded"
# A date must be a real date.
run_capturing env ESCAPE_DATE=2026-13-45 bash "$add" "$hostile" src/a wrong-result https://github.com/o/r/issues/3
assert_eq "$captured_exit_code" "2"
