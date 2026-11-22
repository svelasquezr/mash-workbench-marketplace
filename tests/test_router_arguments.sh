# shellcheck shell=bash
# The router takes text from the session (the range) and from a committed file (.claude/reviewers.toml). Neither may
# reach git as an option, or name a file outside the agents folders.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
finder="$PWD/plugins/review-routing/scripts/python.sh"
script="$PWD/plugins/review-routing/skills/review-changes/reviewers-for-change.py"
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
isolate_git_config
route() { bash "$finder" "$script" "$@"; }
repository="$temporary_directory/repo"
git init --quiet "$repository"
cd "$repository"
mkdir -p src .claude/agents
echo one > src/a.py
git add . && git commit --quiet -m "feat: a"
echo two > src/a.py
git commit --quiet -am "fix: a"

# 1. A range that starts with "-" is not handed to git: "git diff --output=<file>" would write that file.
victim="$temporary_directory/victim.txt"; echo keep > "$victim"
for range in "--output=$victim..HEAD" "--output=$temporary_directory/x/../victim.txt" "-O$victim..HEAD" "--ext-diff..HEAD"; do
  for mode in "" --models --explain; do
    # shellcheck disable=SC2086  # an empty mode is no argument
    run_capturing route $mode -- "$range"
    assert_eq "$captured_exit_code" "2"
    assert_contains "$captured_output" "is not a range"
  done
done
run_capturing route -- "HEAD~1..HEAD --output=$victim"
assert_eq "$captured_exit_code" "2"
assert_contains "$captured_output" "is not a range"
assert_eq "$(cat "$victim")" "keep"
assert_eq "$(find "$temporary_directory" -name 'victim.txt*' | wc -l | tr -d ' ')" "1"
# A real range still works.
assert_eq "$(route HEAD~1..HEAD 2>/dev/null)" "review-routing:change-reviewer"

# 2. A reviewer name in the config is never used as a path: a name with ".." or "/" reads no file outside the agents
#    folders, so a file elsewhere whose frontmatter says "model: haiku" is not opened and not quoted.
printf -- '---\nname: outside\nmodel: haiku-SECRET-VALUE\n---\n' > "$temporary_directory/outside.md"
for name in "../../../outside" "review-routing:../../../../../../../../$temporary_directory/outside" "..\\\\..\\\\outside" ".hidden"; do
  printf 'default_reviewer = "review-routing:change-reviewer"\n[[routes]]\npattern = "^src/"\nreviewers = ["%s"]\n' "$name" > .claude/reviewers.toml
  run_capturing route --models HEAD~1..HEAD
  assert_not_contains "$captured_output" "SECRET-VALUE"
  run_capturing route --check
  assert_not_contains "$captured_output" "SECRET-VALUE"
done
# An agent file that is a symbolic link to a file outside the agents folder is not read either.
ln -s "$temporary_directory/outside.md" .claude/agents/linked.md
printf '[[routes]]\npattern = "^src/"\nreviewers = ["linked", "outside"]\n' > .claude/reviewers.toml
for mode in "--models HEAD~1..HEAD" "--check"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing route $mode
  assert_not_contains "$captured_output" "SECRET-VALUE"
done
rm .claude/agents/linked.md
# A committed .claude/agents that is a symbolic link to a folder outside the repository is not read either: the agent
# files must be inside the repository.
mkdir -p "$temporary_directory/outside-agents"; cp "$temporary_directory/outside.md" "$temporary_directory/outside-agents/outside.md"
mv .claude/agents .claude/agents-real; ln -s "$temporary_directory/outside-agents" .claude/agents
printf '[[routes]]\npattern = "^src/"\nreviewers = ["outside"]\n' > .claude/reviewers.toml
for mode in "--models HEAD~1..HEAD" "--check"; do
  # shellcheck disable=SC2086  # the words are split on purpose
  run_capturing route $mode
  assert_not_contains "$captured_output" "SECRET-VALUE"
done
rm .claude/agents; mv .claude/agents-real .claude/agents
# A project agent on haiku is still found and refused (the check above did not switch the model check off).
printf -- '---\nname: slow\nmodel: haiku\n---\n' > .claude/agents/slow.md
printf '[[routes]]\npattern = "^src/"\nreviewers = ["slow"]\n' > .claude/reviewers.toml
run_capturing route --models HEAD~1..HEAD
assert_contains "$captured_output" "haiku"
[[ "$captured_exit_code" != 0 ]] || { echo "  a haiku reviewer was dispatched"; exit 1; }
echo "router arguments: ok"
