# shellcheck shell=bash
# escape-add.sh and escapes-report.sh: one file per escape in the escapes folder. tests/test_ledger_location.sh covers
# choosing and finding the folder; tests/test_escape_migrate.sh the move from the old one-file ledger.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
add="$PWD/plugins/review-routing/skills/add-reviewer/escape-add.sh"
report="$PWD/plugins/review-routing/skills/add-reviewer/escapes-report.sh"
settings_script="$PWD/plugins/review-routing/scripts/mash-settings.sh"
template="$PWD/plugins/review-routing/skills/add-reviewer/escape-template.md"
# The path checks refuse /tmp, so the fixture lives under $HOME (never under /tmp).
fixture=$(mktemp -d "$HOME/.escapes-test.XXXXXX"); trap 'rm -rf "$fixture"' EXIT
case "$(cd "$fixture" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$fixture"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES ESCAPE_DATE
escapes_folder=.claude/mash-workbench/escapes
# new_repo <name> [<origin>]: a repository with one commit whose escapes folder is the default, chosen in settings.local.
new_repo() {
  local folder
  folder=$(mktemp -d "$fixture/$1.XXXXXX")
  git init --quiet "$folder"
  git -C "$folder" commit --quiet --allow-empty -m "chore: base"
  if [[ -n "${2:-}" ]]; then git -C "$folder" remote add origin "$2"; fi
  bash "$settings_script" set "$folder" escapes "$escapes_folder" --local >/dev/null
  (cd "$folder" && pwd -P)
}
body="$fixture/body.md"
printf 'When the order has a discount, the total includes tax. The total must not include tax. Tax is a separate line.\n' > "$body"
# record <repo> <area> <class> <slug> [more arguments]: escape-add.sh with the shared body file.
record() { local repo=$1 area=$2 class=$3 slug=$4; shift 4; bash "$in_root_script" "$add" "$repo" "$area" "$class" "$slug" --body "$(cat "$body")" "$@"; }
count_files() { find "$1/$escapes_folder" -maxdepth 1 -name '*.md' ! -name README.md | wc -l | tr -d ' '; }
sources() { cat "$1/$escapes_folder"/*-*.md | grep '^source: ' | sort; }

# 1. One record: the exact file the template shows, and a README.md naming the owning repository.
repo=$(new_repo one git@github.com:Acme/Shop.git)
run_capturing env ESCAPE_DATE=2026-11-21 bash "$in_root_script" "$add" "$repo" src/billing wrong-result discount-tax --body "$(cat "$body")" \
  --source "https://github.com/acme/shop/pull/12#discussion_r222"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "recorded: $escapes_folder/2026-11-21-discount-tax.md"
assert_eq "$(cat "$repo/$escapes_folder/2026-11-21-discount-tax.md")" "$(cat "$template")"
assert_eq "$(cat "$repo/$escapes_folder/README.md")" "$(printf '%s\n' '# Review escapes' 'repo: github.com/acme/shop' '' 'One file per bug that a review passed. The add-reviewer skill reads them through escapes-report.sh.')"
# source is optional; the date defaults to today in UTC.
run_capturing record "$repo" src/billing missing-test no-source
assert_eq "$captured_exit_code" "0"
assert_file "$repo/$escapes_folder/$(date -u +%F)-no-source.md"
assert_not_contains "$(cat "$repo/$escapes_folder/$(date -u +%F)-no-source.md")" "source:"

# 2. A folder outside the repo whose README.md names another repository is refused, and nothing is written there.
shared="$fixture/shared-escapes"; mkdir -p "$shared"
printf '# Review escapes\nrepo: github.com/other/thing\n' > "$shared/README.md"
run_capturing env REVIEW_ROUTING_ESCAPES="$shared" bash "$in_root_script" "$add" "$repo" src/a wrong-result other-repo --body "$(cat "$body")"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "owned by github.com/other/thing"
assert_eq "$(find "$shared" -type f | wc -l | tr -d ' ')" "1"
# This repository's own folder outside the repo is fine, spelled in any case.
printf '# Review escapes\nrepo: GitHub.com/Acme/Shop\n' > "$shared/README.md"
run_capturing env REVIEW_ROUTING_ESCAPES="$shared" bash "$in_root_script" "$add" "$repo" src/a wrong-result own-repo --body "$(cat "$body")"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "recorded: $shared/"

# 3. Source dedupe, per area: the same area and source is "already recorded"; the same source in another area is
# another escape (the report counts per area too); the same PR with other review-comment fragments is new.
repo=$(new_repo dedupe git@github.com:acme/shop.git)
record "$repo" src/a wrong-result first --source "https://github.com/acme/shop/pull/7#discussion_r1" >/dev/null
run_capturing record "$repo" src/a other-class again --source "https://github.com/acme/shop/pull/7#discussion_r1"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "already recorded: $escapes_folder/"
assert_contains "$captured_output" "-first.md"
run_capturing record "$repo" src/b other-class other-area --source "https://github.com/acme/shop/pull/7#discussion_r1"
assert_contains "$captured_output" "recorded: $escapes_folder/"
assert_not_contains "$captured_output" "already"
# It still records, and names the file the same source has in the other area.
assert_contains "$captured_output" "also recorded in src/a: $escapes_folder/"
assert_contains "$captured_output" "-first.md"
# A different source prints no hint; the batch prints the hint after its summary line.
run_capturing record "$repo" src/b other-class unrelated --source "https://github.com/acme/shop/pull/99"
assert_not_contains "$captured_output" "also recorded"
rm "$repo/$escapes_folder"/*-unrelated.md
printf -- '---\narea: src/c\nclass: wrong-result\nslug: batch-also\nsource: https://github.com/acme/shop/pull/7#discussion_r1\n---\nA body.\n' > "$fixture/also-batch.md"
run_capturing bash "$in_root_script" "$add" --batch - "$repo" < "$fixture/also-batch.md"
assert_contains "$captured_output" "recorded 1, already recorded 0"
assert_contains "$captured_output" "also recorded in src/a: $escapes_folder/"
rm "$repo/$escapes_folder"/*-batch-also.md
rm "$repo/$escapes_folder"/*-other-area.md
record "$repo" src/a wrong-result second --source "https://github.com/acme/shop/pull/7#discussion_r2" >/dev/null
assert_eq "$(count_files "$repo")" "2"
# On a pull request, a conversation comment and a review keep their fragments too; on an issue they are dropped.
record "$repo" src/f wrong-result comment-1 --source "https://github.com/acme/shop/pull/8#issuecomment-111" >/dev/null
record "$repo" src/f wrong-result comment-2 --source "https://github.com/acme/shop/pull/8#issuecomment-222" >/dev/null
record "$repo" src/f wrong-result review --source "https://github.com/acme/shop/pull/8/changes#pullrequestreview-333" >/dev/null
record "$repo" src/f wrong-result changes-view --source "https://github.com/acme/shop/pull/8/changes#r444" >/dev/null
record "$repo" src/f wrong-result issue-comment --source "https://github.com/acme/shop/issues/8#issuecomment-555" >/dev/null
assert_eq "$(grep -h '^source: ' "$repo/$escapes_folder"/*-comment-?.md "$repo/$escapes_folder"/*-review.md "$repo/$escapes_folder"/*-changes-view.md "$repo/$escapes_folder"/*-issue-comment.md)" \
  "$(printf '%s\n' 'source: https://github.com/acme/shop/pull/8#issuecomment-111' 'source: https://github.com/acme/shop/pull/8#issuecomment-222' \
    'source: https://github.com/acme/shop/pull/8#pullrequestreview-333' 'source: https://github.com/acme/shop/pull/8#discussion_r444' 'source: https://github.com/acme/shop/issues/8')"
rm "$repo/$escapes_folder"/*-comment-?.md "$repo/$escapes_folder"/*-review.md "$repo/$escapes_folder"/*-changes-view.md "$repo/$escapes_folder"/*-issue-comment.md
# /pull/N and /issues/N with no fragment name the same number: in one area they are one escape (a migrated entry is
# /issues/N, a new record of the same pull request /pull/N); in another area they are not.
record "$repo" src/g wrong-result migrated --source "https://github.com/acme/shop/issues/9" >/dev/null
run_capturing record "$repo" src/g wrong-result as-pull --source "https://github.com/acme/shop/pull/9"
assert_contains "$captured_output" "already recorded"
assert_contains "$captured_output" "-migrated.md"
record "$repo" src/g wrong-result pull-first --source "https://github.com/acme/shop/pull/10" >/dev/null
run_capturing record "$repo" src/g wrong-result as-issue --source "acme/shop#10"
assert_contains "$captured_output" "already recorded"
run_capturing record "$repo" src/g wrong-result fragment --source "https://github.com/acme/shop/pull/9#discussion_r5"
assert_not_contains "$captured_output" "already"
run_capturing record "$repo" src/h wrong-result other-area --source "https://github.com/acme/shop/pull/9"
assert_not_contains "$captured_output" "already"
rm "$repo/$escapes_folder"/*-migrated.md "$repo/$escapes_folder"/*-pull-first.md "$repo/$escapes_folder"/*-fragment.md "$repo/$escapes_folder"/*-other-area.md
# The files view spells a review comment #r<id>: the same comment as #discussion_r<id>.
run_capturing record "$repo" src/a wrong-result files-view --source "https://github.com/acme/shop/pull/7/files#r2"
assert_contains "$captured_output" "already recorded"
# Other fragments, a query and a trailing slash are dropped from GitHub links.
record "$repo" src/a wrong-result issue --source "https://github.com/acme/shop/issues/5" >/dev/null
for spelling in "https://www.github.com/Acme/Shop/issues/5#issuecomment-1" "https://github.com/acme/shop/issues/5?notification_referrer_id=x" \
  "HTTPS://GitHub.com/Acme/Shop/issues/5/" "acme/shop#5" "#5"; do
  run_capturing record "$repo" src/a wrong-result spelling --source "$spelling"
  assert_eq "$captured_exit_code" "0"
  assert_contains "$captured_output" "already recorded"
done
# A link that only contains a recorded one is a different bug.
record "$repo" src/a wrong-result longer --source "https://github.com/acme/shop/issues/50" >/dev/null
assert_eq "$(count_files "$repo")" "4"
# Processed files no longer count for the dedupe.
mkdir -p "$repo/$escapes_folder/processed"
mv "$repo/$escapes_folder"/*-longer.md "$repo/$escapes_folder/processed/"
run_capturing record "$repo" src/a wrong-result longer-again --source "https://github.com/acme/shop/issues/50"
assert_contains "$captured_output" "recorded: "
assert_not_contains "$captured_output" "already"

# 4. Link spellings: /pull/N stays /pull/N; owner/repo#N becomes /issues/N; #N takes owner/repo from the origin.
repo=$(new_repo links git@github.com:Acme/Shop.git)
record "$repo" src/a wrong-result pull --source "https://github.com/Acme/Shop/pull/12/" >/dev/null
record "$repo" src/a wrong-result short --source "Acme/Shop#13" >/dev/null
record "$repo" src/a wrong-result number --source "#14" >/dev/null
record "$repo" src/a wrong-result checks --source "https://github.com/acme/shop/pull/15/checks" >/dev/null
record "$repo" src/a wrong-result other --source "https://tracker.example/bugs/42/" >/dev/null
record "$repo" src/a wrong-result gitlab --source "https://gitlab.example/g/p/-/merge_requests/3#note_99" >/dev/null
assert_eq "$(sources "$repo")" "$(printf '%s\n' 'source: https://github.com/acme/shop/issues/13' 'source: https://github.com/acme/shop/issues/14' \
  'source: https://github.com/acme/shop/pull/12' 'source: https://github.com/acme/shop/pull/15' 'source: https://gitlab.example/g/p/-/merge_requests/3#note_99' \
  'source: https://tracker.example/bugs/42')"
# #N with no GitHub origin is refused, and nothing is written.
repo=$(new_repo no-origin)
run_capturing record "$repo" src/a wrong-result no-origin --source "#52"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "origin"
[[ ! -e "$repo/$escapes_folder" ]] || { echo "  wrote before refusing the link"; exit 1; }
# #N resolves through an origin with credentials or a trailing slash; the credentials never reach the file.
for origin_url in 'https://user:TOKEN@github.com/O/R.git' 'git@github.com:O/R/' 'https://github.com/O/R/'; do
  repo=$(new_repo origin "$origin_url")
  record "$repo" src/a wrong-result number --source "#9" >/dev/null
  assert_eq "$(sources "$repo")" "source: https://github.com/o/r/issues/9"
  assert_not_contains "$(cat "$repo/$escapes_folder"/*)" "TOKEN"
done
# A link that is not a web link is refused.
for bad_link in 'javascript:alert(1)' '/etc/passwd' 'not a link at all' ''; do
  run_capturing record "$repo" src/a wrong-result bad-link --source "$bad_link"
  assert_eq "$captured_exit_code" "2"
done

# 5. A name that exists gets -2, then -3.
repo=$(new_repo collide)
for _ in 1 2 3; do ESCAPE_DATE=2026-11-21 record "$repo" src/a wrong-result same-name >/dev/null; done
for name in 2026-11-21-same-name.md 2026-11-21-same-name-2.md 2026-11-21-same-name-3.md; do assert_file "$repo/$escapes_folder/$name"; done
# A name already in processed/ is not used again, so moving files there never meets a clash.
mkdir -p "$repo/$escapes_folder/processed"
mv "$repo/$escapes_folder/2026-11-21-same-name.md" "$repo/$escapes_folder/2026-11-21-same-name-2.md" "$repo/$escapes_folder/processed/"
ESCAPE_DATE=2026-11-21 record "$repo" src/a wrong-result same-name >/dev/null
assert_file "$repo/$escapes_folder/2026-11-21-same-name-4.md"
[[ ! -e "$repo/$escapes_folder/2026-11-21-same-name.md" ]] || { echo "  reused a name that processed/ holds"; exit 1; }

# 6. Batch: one bad block writes nothing; a good batch prints one summary line.
repo=$(new_repo batch git@github.com:acme/shop.git)
batch="$fixture/batch.txt"
printf -- '---\narea: src/a\nclass: wrong-result\nslug: one\n---\nFirst.\n---8<---\n---\narea: src/a\nclass: Bad Class\nslug: two\n---\nSecond.\n' > "$batch"
run_capturing bash "$in_root_script" "$add" --batch - "$repo" < "$batch"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "block 2"
[[ ! -e "$repo/$escapes_folder" ]] || { echo "  a batch with a bad block wrote something"; exit 1; }
for bad_block in 'area: src/a\nclass: c\n---\nno slug' 'area: src/a\nclass: c\nslug: s\n---\n\n' 'area: src/a\nclass: c\nslug: s\ncolour: red\n---\nx' \
  'area: src/a\nclass: c\nslug: s\ndate: 2026-02-30\n---\nx' 'area: src/a\nclass: c\nslug: s\nsource: javascript:x\n---\nx'; do
  # shellcheck disable=SC2059  # the block is the format on purpose: its \n are line breaks
  printf -- "---\n$bad_block\n" > "$batch"
  run_capturing bash "$in_root_script" "$add" --batch - "$repo" < "$batch"
  assert_eq "$captured_exit_code" "2"
done
record "$repo" src/a wrong-result known --source "https://github.com/acme/shop/issues/1" >/dev/null
printf -- '---\ndate: 2026-11-20\narea: src/a\nclass: wrong-result\nslug: b-one\nsource: acme/shop#1\n---\nKnown.\n---8<---\n\n---\narea: ./src/b/\nclass: data-loss\nslug: b-two\n---\r\nTwo.\r\n---8<---\n---\narea: src/b\nclass: data-loss\nslug: b-three\nsource: https://github.com/acme/shop/issues/3\n---\nThree.\n---8<---\n' > "$batch"
run_capturing env ESCAPE_DATE=2026-11-21 bash "$in_root_script" "$add" --batch - "$repo" < "$batch"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "recorded 2, already recorded 1"
assert_eq "$(cat "$repo/$escapes_folder/2026-11-21-b-two.md")" "$(printf -- '---\ndate: 2026-11-21\narea: src/b\nclass: data-loss\n---\n\nTwo.')"
# The block that reaches the threshold prints its area's report line after the summary.
printf -- '---\ndate: 2026-11-22\narea: src/b\nclass: wrong-result\nslug: b-four\n---\nFour.\n' > "$batch"
run_capturing bash "$in_root_script" "$add" --batch - "$repo" < "$batch"
assert_contains "$captured_output" "recorded 1, already recorded 0"
assert_contains "$captured_output" "src/b: 3 escapes (data-loss 2, wrong-result 1) -> add a reviewer for src/b (add-reviewer skill)"
# --batch opens no file: a path is refused (exit 2) and nothing of the file is shown or written.
printf -- '---\nsecret-key: hunter2\n---\n' > "$fixture/secret-batch"
run_capturing bash "$in_root_script" "$add" --batch "$fixture/secret-batch" "$repo"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "standard input only"
assert_not_contains "$captured_output" "hunter2"

# 7. --list: one line per file in the area, newest first, at most 20, then "and N more".
repo=$(new_repo list)
: > "$batch"
for day in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22; do
  printf -- '---\ndate: 2026-10-%s\narea: src/list\nclass: wrong-result\nslug: day-%s\n---\n\nSummary of day %s.\nMore detail.\n---8<---\n' "$day" "$day" "$day" >> "$batch"
done
printf -- '---\narea: src/other\nclass: wrong-result\nslug: other\n---\nOther area.\n' >> "$batch"
bash "$in_root_script" "$add" --batch - "$repo" < "$batch" >/dev/null
run_capturing bash "$in_root_script" "$add" --list "$repo" src/list/
assert_eq "$captured_exit_code" "0"
assert_eq "$(printf '%s\n' "$captured_output" | head -1)" "2026-10-22-day-22.md  Summary of day 22."
assert_eq "$(printf '%s\n' "$captured_output" | sed -n 20p)" "2026-10-03-day-03.md  Summary of day 03."
assert_eq "$(printf '%s\n' "$captured_output" | tail -1)" "and 2 more"
assert_eq "$(printf '%s\n' "$captured_output" | wc -l | tr -d ' ')" "21"
assert_not_contains "$captured_output" "Other area"
run_capturing bash "$in_root_script" "$add" --list "$repo" src/none
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "no escapes in src/none"
run_capturing bash "$in_root_script" "$add" --list "$repo"
assert_eq "$captured_exit_code" "2"

# 8. Report: files per area with their classes, most first; the threshold is 3 by default, the setting changes it, and
# --threshold wins over the setting.
repo=$(new_repo report)
run_capturing bash "$report" "$repo"
assert_eq "$captured_exit_code" "0"
assert_eq "$captured_output" "no escapes recorded"
record "$repo" docs stale-doc d1 >/dev/null
record "$repo" ./src/payments/ missing-test p1 >/dev/null
record "$repo" src/payments wrong-claim p2 >/dev/null
run_capturing bash "$report" "$repo"
assert_eq "$captured_output" "$(printf '%s\n' 'src/payments: 2 escapes (missing-test 1, wrong-claim 1)' 'docs: 1 escape (stale-doc 1)')"
run_capturing record "$repo" src/payments wrong-claim p3
assert_contains "$captured_output" "src/payments: 3 escapes (missing-test 1, wrong-claim 2) -> add a reviewer for src/payments (add-reviewer skill)"
assert_not_contains "$captured_output" "docs:"
bash "$settings_script" set "$repo" escapes.threshold 1 --team >/dev/null
assert_contains "$(bash "$report" "$repo")" "docs: 1 escape (stale-doc 1) -> add a reviewer for docs"
run_capturing bash "$report" "$repo" --threshold 5
assert_not_contains "$captured_output" "add a reviewer"
bash "$settings_script" set "$repo" escapes.threshold zero --team >/dev/null
run_capturing bash "$report" "$repo"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "escapes.threshold"
assert_contains "$captured_output" "src/payments: 3 escapes (missing-test 1, wrong-claim 2) -> add a reviewer"
assert_not_contains "$captured_output" "docs: 1 escape (stale-doc 1) ->"
# README.md, processed/ and files without frontmatter do not count.
mkdir -p "$repo/$escapes_folder/processed"
mv "$repo/$escapes_folder"/*-p3.md "$repo/$escapes_folder/processed/"
printf 'notes, not an escape\n' > "$repo/$escapes_folder/notes.md"
: > "$repo/$escapes_folder/empty.md"
assert_eq "$(bash "$report" "$repo" --threshold 3 | head -1)" "src/payments: 2 escapes (missing-test 1, wrong-claim 1)"
# Usage errors.
for bad in "--threshold zero" "--threshold" "--frobnicate"; do
  # shellcheck disable=SC2086  # split on purpose
  run_capturing bash "$report" "$repo" $bad
  assert_eq "$captured_exit_code" "2"
done
run_capturing bash "$report" "$fixture/does-not-exist"
assert_eq "$captured_exit_code" "2"

# 9. Report extras: the concentration note, and a decline that hides the suffix until the count reaches count + 2.
repo=$(new_repo extras git@github.com:acme/shop.git)
record "$repo" src/c wrong-result c1 --source "https://github.com/acme/shop/pull/7#discussion_r1" >/dev/null
record "$repo" src/c wrong-result c2 --source "https://github.com/acme/shop/pull/7#discussion_r2" >/dev/null
record "$repo" src/c data-loss c3 --source "https://github.com/acme/shop/issues/9" >/dev/null
assert_eq "$(bash "$report" "$repo")" "src/c: 3 escapes (wrong-result 2, data-loss 1) (2 from one source: https://github.com/acme/shop/pull/7) -> add a reviewer for src/c (add-reviewer skill)"
bash "$settings_script" set "$repo" declined.src/c 2026-11-01:3 --local >/dev/null
assert_eq "$(bash "$report" "$repo")" "src/c: 3 escapes (wrong-result 2, data-loss 1) (2 from one source: https://github.com/acme/shop/pull/7) (declined on 2026-11-01)"
run_capturing record "$repo" src/c data-loss c4
assert_not_contains "$captured_output" "add a reviewer"
assert_contains "$(bash "$report" "$repo")" "src/c: 4 escapes (wrong-result 2, data-loss 2) (declined on 2026-11-01)"
run_capturing record "$repo" src/c data-loss c5
assert_contains "$captured_output" "src/c: 5 escapes (wrong-result 2, data-loss 3) -> add a reviewer for src/c (add-reviewer skill)"
# A decline value in another shape is ignored.
bash "$settings_script" set "$repo" declined.src/c soon --local >/dev/null
assert_contains "$(bash "$report" "$repo")" "-> add a reviewer for src/c"
# Concentration needs more than half: exactly half (2 of 4) gets no note. One escape is never a concentration, though
# it is all of its area's escapes. A migrated /issues/N and a new /pull/N#fragment are one pull request.
record "$repo" src/half wrong-result h1 --source "https://github.com/acme/shop/pull/3#discussion_r1" >/dev/null
record "$repo" src/half wrong-result h2 --source "https://github.com/acme/shop/pull/3#discussion_r2" >/dev/null
record "$repo" src/half wrong-result h3 --source "https://github.com/acme/shop/issues/4" >/dev/null
record "$repo" src/half wrong-result h4 >/dev/null
record "$repo" src/one wrong-result o1 --source "https://github.com/acme/shop/pull/5" >/dev/null
record "$repo" src/mixed wrong-result m1 --source "https://github.com/acme/shop/issues/6" >/dev/null
record "$repo" src/mixed wrong-result m2 --source "https://github.com/acme/shop/pull/6#discussion_r9" >/dev/null
assert_contains "$(bash "$report" "$repo")" "src/half: 4 escapes (wrong-result 4) -> add a reviewer"
assert_contains "$(bash "$report" "$repo")" "src/one: 1 escape (wrong-result 1)"
assert_not_contains "$(bash "$report" "$repo")" "1 from one source"
assert_contains "$(bash "$report" "$repo")" "src/mixed: 2 escapes (wrong-result 2) (2 from one source: https://github.com/acme/shop/issues/6)"

# 11. CRLF and blank lines around the body: the file gets \n line endings and starts with the first real line.
repo=$(new_repo crlf)
printf '\r\n\r\nFirst line.\r\nSecond line.\r\n\r\n' > "$fixture/crlf-body.md"
ESCAPE_DATE=2026-11-21 bash "$in_root_script" "$add" "$repo" src/a wrong-result crlf --body "$(cat "$fixture/crlf-body.md")" >/dev/null
assert_eq "$(cat "$repo/$escapes_folder/2026-11-21-crlf.md")" "$(printf -- '---\ndate: 2026-11-21\narea: src/a\nclass: wrong-result\n---\n\nFirst line.\nSecond line.')"
assert_eq "$(grep -c $'\r' "$repo/$escapes_folder/2026-11-21-crlf.md" || true)" "0"
assert_eq "$(bash "$in_root_script" "$add" --list "$repo" src/a)" "2026-11-21-crlf.md  First line."

# Field checks, as before the move to files: areas are normalised; absolute, parent, dot, file and whitespace areas are
# refused; the class and the slug are lowercase words joined by hyphens; a line break in any field is refused.
repo=$(new_repo fields)
record "$repo" src//payments// missing-test normal >/dev/null
assert_contains "$(cat "$repo/$escapes_folder"/*-normal.md)" "area: src/payments"
mkdir -p "$repo/src/payments"; printf 'x\n' > "$repo/src/payments/refund.py"
run_capturing record "$repo" src/payments/refund.py missing-test file-area
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "a directory"
for bad_area in /abs ../x . ./ $'src/pay\tments' "src/payments " $'src/a\r' $'two\nlines' ""; do
  run_capturing record "$repo" "$bad_area" missing-test bad-area
  assert_eq "$captured_exit_code" "2"
done
for bad_class in 'oops @octocat [x](http://evil)' Wrong-Result "miss · ing" $'two\nlines' ""; do
  run_capturing record "$repo" src/a "$bad_class" bad-class
  assert_eq "$captured_exit_code" "2"
done
for bad_slug in Upper "two words" "-lead" "trail-" "a--b" "" "$(printf 'x%.0s' {1..61})"; do
  run_capturing record "$repo" src/a wrong-result "$bad_slug"
  assert_eq "$captured_exit_code" "2"
done
record "$repo" src/a wrong-result "$(printf 'x%.0s' {1..60})" >/dev/null
# The body must hold a non-empty line, on standard input or as text; --body is required.
printf '\n  \n' > "$fixture/blank-body.md"
run_capturing bash "$in_root_script" "$add" "$repo" src/a wrong-result bad-body --body "$(cat "$fixture/blank-body.md")"
assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$add" "$repo" src/a wrong-result bad-body --body "  "
assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$add" "$repo" src/a wrong-result no-body
assert_eq "$captured_exit_code" "2"
run_capturing bash "$in_root_script" "$add" "$repo" src/a wrong-result no-body --body
assert_eq "$captured_exit_code" "2"
# --body takes the text itself: the file is what the text says, also when the text is a path.
run_capturing env ESCAPE_DATE=2026-11-21 bash "$in_root_script" "$add" "$repo" src/text wrong-result body-text --body "When the order has a discount, the total includes tax."
assert_eq "$captured_exit_code" "0"
assert_eq "$(tail -n 1 "$repo/$escapes_folder/2026-11-21-body-text.md")" "When the order has a discount, the total includes tax."
# No argument makes the script open a file: --body-file is gone (it copied any readable file, a private key for
# example, into the escapes folder with no prompt once an allow rule covered the script), and a path given as the
# body text is recorded as text.
printf 'PRIVATE KEY hunter2\n' > "$fixture/secret"
files_before=$(count_files "$repo")
run_capturing bash "$in_root_script" "$add" "$repo" src/text wrong-result steal --body-file "$fixture/secret"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "--body-file is gone"
assert_eq "$(count_files "$repo")" "$files_before"
run_capturing env ESCAPE_DATE=2026-11-21 bash "$in_root_script" "$add" "$repo" src/text wrong-result path-as-text --body "$fixture/secret"
assert_eq "$captured_exit_code" "0"
assert_eq "$(tail -n 1 "$repo/$escapes_folder/2026-11-21-path-as-text.md")" "$fixture/secret"
if grep -rq hunter2 "$repo/$escapes_folder"; then echo "  a file named in an argument was copied into the escapes folder"; exit 1; fi
# A committed symbolic link as the folder's README.md would be written through: refused, nothing recorded.
link_repo=$(new_repo readme-link)
mkdir -p "$link_repo/$escapes_folder"; ln -s "$fixture/planted-readme" "$link_repo/$escapes_folder/README.md"
run_capturing record "$link_repo" src/a wrong-result through-link
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "symbolic link"
[[ ! -e "$fixture/planted-readme" ]] || { echo "  wrote through a symbolic link"; exit 1; }
assert_eq "$(count_files "$link_repo")" "0"
# The committed team file cannot send escapes outside the repository (here: into another project's .claude/rules).
team_repo=$(new_repo team-outside)
bash "$settings_script" unset "$team_repo" escapes --local >/dev/null
mkdir -p "$fixture/victim/.claude"
printf 'escapes=../victim/.claude/rules\n' > "$team_repo/.claude/mash-workbench/settings"
run_capturing record "$team_repo" src/x wrong-result some-slug
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "outside the repository"
[[ ! -e "$fixture/victim/.claude/rules" ]] || { echo "  the team settings file sent an escape outside the repository"; exit 1; }
run_capturing bash "$report" "$team_repo"
assert_eq "$captured_exit_code" "6"
run_capturing bash "$in_root_script" "$add" --list "$team_repo" src/x
assert_eq "$captured_exit_code" "6"
# The user's own settings.local may choose it.
bash "$settings_script" set "$team_repo" escapes "$fixture/victim/own-escapes" --local >/dev/null
run_capturing record "$team_repo" src/x wrong-result some-slug
assert_eq "$captured_exit_code" "0"
run_capturing bash "$in_root_script" "$add" "$repo" src/a wrong-result s --body "$(cat "$body")" --frobnicate
assert_eq "$captured_exit_code" "2"
# The date override must be a real date; 29 February only in a leap year.
for bad_date in 'x; rm -rf /' 2026-13-45 2026-02-29 2026-04-31 2026-00-10 2026-01-00 0000-01-01 2100-02-29; do
  run_capturing env ESCAPE_DATE="$bad_date" bash "$in_root_script" "$add" "$repo" src/a wrong-result bad-date --body "$(cat "$body")"
  assert_eq "$captured_exit_code" "2"
done
for good_date in 2028-02-29 2000-02-29 2026-12-31; do
  ESCAPE_DATE="$good_date" record "$repo" src/a wrong-result good-date >/dev/null
  assert_file "$repo/$escapes_folder/$good_date-good-date.md"
done
# A backslash in the area is kept as typed, so the threshold line is still printed for it.
repo=$(new_repo backslash)
record "$repo" 'src/b\n' wrong-result b1 >/dev/null
record "$repo" 'src/b\n' wrong-result b2 >/dev/null
run_capturing record "$repo" 'src/b\n' wrong-result b3
assert_contains "$captured_output" '-> add a reviewer for src/b\n'

# No Python needed: with python3 as the Windows Store stub (prints a message, exits 9009), recording still works.
stub_bin="$fixture/stub-bin"; mkdir -p "$stub_bin"
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9009\n' > "$stub_bin/python3"
chmod +x "$stub_bin/python3"
repo=$(new_repo no-python)
run_capturing env PATH="$stub_bin:$PATH" bash "$in_root_script" "$add" "$repo" src/a wrong-result stub --body "$(cat "$body")"
assert_eq "$captured_exit_code" "0"
assert_file "$repo/$escapes_folder/$(date -u +%F)-stub.md"
assert_eq "$(env PATH="$stub_bin:$PATH" bash "$report" "$repo")" "src/a: 1 escape (wrong-result 1)"

# The definition and the escape: field are written everywhere they matter; the prose names the threshold, not 2.
for file in plugins/review-routing/agents/change-reviewer.md plugins/review-routing/skills/add-reviewer/reviewer-template.md; do
  assert_contains "$(cat "$file")" "escape: yes"
  assert_contains "$(cat "$file")" "escape: no"
  assert_contains "$(cat "$file")" "an earlier review passed"
  assert_contains "$(cat "$file")" "predates any review"
done
assert_contains "$(cat plugins/review-routing/skills/add-reviewer/SKILL.md)" "the escape threshold (default 3)"
assert_contains "$(cat plugins/review-routing/skills/review-changes/reference.md)" "-> add a reviewer for"
assert_contains "$(cat plugins/review-routing/skills/review-changes/SKILL.md)" "source link, when there is one"
assert_not_contains "$(cat plugins/review-routing/skills/review-changes/SKILL.md)" "issue link"
assert_not_contains "$(cat "$add")" "ESCAPE_THRESHOLD"
# Bash 3.2 (macOS) has no ${var,,} lowercasing: the scripts lowercase with tr.
if grep -q ',,}' "$add" "$report"; then echo "FAIL: bash-4-only \${var,,} in the escape scripts" >&2; exit 1; fi

# The hand-recording rules in the review-changes reference hold every line of the template, so they cannot drift.
while IFS= read -r template_line; do
  [[ -z "$template_line" ]] || assert_contains "$(cat plugins/review-routing/skills/review-changes/reference.md)" "$template_line"
done < "$template"

# A committed symbolic link named like an escape file is not read: --list and the report would print lines of the file
# it points at.
leak_repo=$(new_repo leak)
record "$leak_repo" src/a wrong-result real >/dev/null
printf -- '---\ndate: 2026-01-01\narea: src/a\nclass: wrong-result\n---\n\nTOPSECRET first body line\n' > "$fixture/elsewhere.md"
ln -s "$fixture/elsewhere.md" "$leak_repo/$escapes_folder/2026-01-01-leak.md"
run_capturing bash "$in_root_script" "$add" --list "$leak_repo" src/a
assert_not_contains "$captured_output" "TOPSECRET"
assert_contains "$(bash "$report" "$leak_repo")" "src/a: 1 escape "

# A settings.local that the repository committed is not the user's own file: in a fresh clone it cannot send escapes
# outside the repository.
origin_repo=$(new_repo committed-local)
printf 'escapes=%s\n' "$fixture/victim/.claude/rules" > "$origin_repo/.claude/mash-workbench/settings.local"
git -C "$origin_repo" add -f .claude/mash-workbench/settings.local
git -C "$origin_repo" commit --quiet -m "chore: a committed settings.local"
git clone --quiet "$origin_repo" "$fixture/committed-local-clone"
run_capturing record "$fixture/committed-local-clone" src/x wrong-result injected
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "outside the repository"
[[ ! -e "$fixture/victim/.claude/rules" ]] || { echo "  a committed settings.local sent an escape outside the repository"; exit 1; }

# One record reads no standard input: "--body - < .env" would copy a file of the project under an allow rule.
stdin_repo=$(new_repo no-stdin)
printf 'API_KEY=hunter2\n' > "$stdin_repo/.env"
run_capturing bash "$in_root_script" "$add" "$stdin_repo" src/a wrong-result from-stdin --body - < "$stdin_repo/.env"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "standard input is not read"
[[ ! -e "$stdin_repo/$escapes_folder" ]] || { echo "  a record was written from standard input"; exit 1; }
# "<no such name>/../<committed link>" in the committed settings: refused, nothing written outside.
ln -s ../victim/.claude "$stdin_repo/link"
bash "$settings_script" unset "$stdin_repo" escapes --local >/dev/null
printf 'escapes=nope/../link/rules\n' > "$stdin_repo/.claude/mash-workbench/settings"
run_capturing record "$stdin_repo" src/a wrong-result through-dots
assert_eq "$captured_exit_code" "6"
[[ ! -e "$fixture/victim/.claude/rules" && ! -e "$stdin_repo/nope" ]] || { echo "  wrote through a link behind .."; exit 1; }
