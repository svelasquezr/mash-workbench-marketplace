# shellcheck shell=bash
# reviewer-guard (review-routing): a reviewer subagent may not change a real git checkout or write to GitHub via Bash.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
guard="$PWD/plugins/review-routing/hooks/reviewer-guard.py"
hooks_json="$PWD/plugins/review-routing/hooks/hooks.json"
# The guard also counts /tmp and /var/tmp as temporary, so the whole fixture lives under $HOME (never under those).
area=$(mktemp -d "$HOME/.reviewer-guard-test.XXXXXX"); trap 'rm -rf "$area"' EXIT
case "$(realpath "$area")" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$area"
isolate_git_config

# The guard treats a repository as throwaway when its git dir is under tempfile.gettempdir(). The hook process gets
# TMPDIR=$scratch, so $scratch is "the temp dir" for it and $real (outside it, yet inside $area for cleanup) is a real repo.
scratch="$area/scratch"; real="$area/real"; home_directory="$area/home"; plugin_root="$area/plugin"
mkdir -p "$scratch" "$real" "$home_directory/.claude/agents" "$plugin_root/agents"
repository="$real/repository"; worktree="$real/worktree"; throwaway="$scratch/throwaway"
git init --quiet -b main "$repository"
git -C "$repository" commit --quiet --allow-empty -m "chore: base"
git -C "$repository" worktree add --quiet -b feature "$worktree"
git init --quiet -b main "$throwaway"
git -C "$throwaway" commit --quiet --allow-empty -m "chore: base"
mkdir -p "$repository/.claude/agents"
printf 'Review it. End with SAFE TO LAND or NOT SAFE.\n' > "$repository/.claude/agents/gatekeeper.md"
printf 'Builds things.\n' > "$repository/.claude/agents/builder.md"
mkdir -p "$worktree/.claude/agents"
cp "$repository/.claude/agents/gatekeeper.md" "$worktree/.claude/agents/gatekeeper.md"
printf 'Review it. End with SAFE TO LAND or NOT SAFE.\n' > "$home_directory/.claude/agents/home-gate.md"
printf 'Review it. End with SAFE TO LAND or NOT SAFE.\n' > "$plugin_root/agents/plugin-gate.md"
# The project names its reviewers in .claude/reviewers.toml; only those (and review-routing's own agents) are guarded.
printf '%s\n' 'default_reviewer = "gatekeeper"' '[[routes]]' "pattern = '^src/'" 'reviewers = ["payments-reviewer", "someplugin:db-reviewer"]' > "$repository/.claude/reviewers.toml"
cp "$repository/.claude/reviewers.toml" "$worktree/.claude/reviewers.toml"
printf 'Review payments.\n' > "$repository/.claude/agents/payments-reviewer.md"
cp "$repository/.claude/agents/payments-reviewer.md" "$worktree/.claude/agents/payments-reviewer.md"
# A config may name Claude Code's built-in general-purpose agent as the default reviewer.
generic="$real/generic"; git init --quiet -b main "$generic"; mkdir -p "$generic/.claude"
printf '%s\n' 'default_reviewer = "general-purpose"' > "$generic/.claude/reviewers.toml"
printf 'Loop until the reviewer says SAFE TO LAND.\n' > "$repository/.claude/agents/marker-builder.md"
broken="$real/broken"; git init --quiet -b main "$broken"; mkdir -p "$broken/.claude"
printf 'reviewers = [unclosed\n' > "$broken/.claude/reviewers.toml"

# payload <agent_type|-> <cwd> <command>: the PreToolUse JSON; "-" leaves agent_type out.
payload() {
  python3 -c '
import json, sys
agent, cwd, command = sys.argv[1:4]
data = {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command}}
if agent != "-": data["agent_type"] = agent
print(json.dumps(data))' "$1" "$2" "$3"
}
# run_guard <json>: runs the hook the way Claude Code would, with the temp dir the guard sees set to $scratch.
run_guard() {
  run_capturing env TMPDIR="$scratch" HOME="$home_directory" CLAUDE_PLUGIN_ROOT="$plugin_root" python3 "$guard" <<< "$1"
}
agent="review-routing:change-reviewer"
# blocked/allowed <command> [cwd] [agent]: run as a reviewer in the real repository unless told otherwise.
blocked() {
  run_guard "$(payload "${3-$agent}" "${2:-$repository}" "$1")"
  if [[ "$captured_exit_code" != 2 ]]; then printf '  expected blocked: %s\n  got %s: %s\n' "$1" "$captured_exit_code" "$captured_output"; exit 1; fi
  [[ -n "$captured_output" ]] || { echo "  no reason given for: $1"; exit 1; }
}
allowed() {
  run_guard "$(payload "${3-$agent}" "${2:-$repository}" "$1")"
  if [[ "$captured_exit_code" != 0 ]]; then printf "  expected allowed: %s (cwd %s, agent %s)\n  got %s: %s\n" "$1" "${2:-$repository}" "${3-$agent}" "$captured_exit_code" "$captured_output"; exit 1; fi
}

# 1. The recorded incidents, verbatim in shape.
blocked "cd $worktree; git checkout -q origin/feature-plugin" "$scratch"
blocked "git checkout pr81"
blocked "git fetch origin pull/81/head:pr81"
blocked "git --work-tree=/tmp/x checkout FETCH_HEAD -- src tests"
blocked "GIT_INDEX_FILE=$scratch/index git --work-tree=/tmp/x checkout FETCH_HEAD -- src tests"
blocked "export GIT_INDEX_FILE=$scratch/index; git --work-tree=$scratch/x checkout FETCH_HEAD -- src tests"
blocked "git reset"
blocked "git -C $worktree checkout origin/feature-plugin"
blocked "git checkout -q origin/feature-plugin" "$worktree"
run_guard "$(payload "$agent" "$repository" "git checkout pr81")"
assert_contains "$captured_output" 'git show <ref>:<path>'
assert_contains "$captured_output" 'git archive'
assert_contains "$captured_output" 'mktemp -d'
assert_contains "$captured_output" 'git checkout pr81'

# 2. Allow-list entries and a refused near miss each (run in the real repository).
for command in "git show HEAD:README.md" "git diff main...HEAD -- src" "git log --oneline -5" "git blame README.md" "git status --short" \
  "git grep -n foo" "git ls-files" "git ls-tree HEAD" "git rev-parse HEAD" "git rev-list HEAD" "git merge-base main HEAD" \
  "git cat-file -p HEAD" "git describe --tags" "git for-each-ref refs/heads" "git shortlog -sn" "git archive HEAD | tar -x -C \"\$(mktemp -d)\"" \
  "git -c core.pager=cat log" "git --no-pager diff" "git -C $worktree log" "git log | head -3" "git diff 2>/dev/null" "git diff > /dev/null 2>&1" \
  "git branch" "git branch -a" "git branch -vv" "git branch --contains HEAD" "git branch --list 'pr*'" "git branch --show-current" "git branch --merged main" \
  "git tag" "git tag -l 'v*'" "git tag --contains HEAD" "git config --get user.name" "git config --list" "git remote" "git remote -v" \
  "git stash list" "git stash show -p" "git apply --check change.patch" "git apply --stat change.patch" \
  "git init" "git clone https://github.com/o/r.git" "git reflog" "git reflog show HEAD" "git show-branch" "git whatchanged" \
  "git count-objects -v" "git fsck" "git remote show origin" "git remote -v show origin" "git config user.name" "git tag -v v1" \
  "git config --file x user.name" "git config -f x user.name" "git config --blob HEAD:x user.name" "git config --file=x user.name" "git init -q \$tmp" \
  "git fetch" "git fetch origin" "git fetch origin pull/1/head" "git fetch --depth 1 origin main" "git worktree list" "git ls-remote origin"; do
  allowed "$command"
done
for command in "git branch -D x" "git branch -d x" "git branch pr1" "git branch -m old new" "git branch -f x HEAD" "git branch --set-upstream-to=origin/x" \
  "git tag v1" "git tag -d v1" "git config user.name x" "git config --unset user.name" "git remote add x url" "git remote remove origin" \
  "git stash" "git stash pop" "git stash push" "git apply change.patch" "git apply --check --apply change.patch" \
  "git fetch origin pull/1/head:pr1" "git fetch origin +refs/heads/*:refs/remotes/x/*" "git worktree remove x" "git worktree add ../x main" \
  "git checkout main" "git switch main" "git restore x" "git commit -m x" "git add ." "git merge main" "git rebase main" "git pull" "git push" \
  "git cherry-pick HEAD" "git clean -fd" "git update-ref -d refs/heads/x" "git reset --hard" "git rm x" "git mv a b"; do
  blocked "$command"
done
run_guard "$(payload "$agent" "$repository" "git diff main...HEAD")"
assert_eq "$captured_exit_code" "0"

# gh: refused wherever it runs; reads stay.
for command in "gh pr checkout 5" "gh pr merge 5 --squash" "gh pr close 5" "gh pr reopen 5" "gh pr edit 5 --title x" "gh pr comment 5 -b x" \
  "gh pr review 5 --approve" "gh pr ready 5" "gh pr create --fill" "gh issue create -t x" "gh issue comment 3 -b x" "gh issue close 3" \
  "gh issue edit 3" "gh issue reopen 3" "gh api -X POST repos/x/issues" "gh api --method DELETE repos/x/issues/1" "gh api --method=PUT repos/x/y" \
  "gh api -XPATCH repos/x/issues/1" "gh api repos/x/issues -f title=x" "gh -R o/r pr merge 5" "gh --repo o/r issue create"; do
  blocked "$command" "$scratch"
done
for command in "gh pr diff 5" "gh pr view 5 --json files" "gh pr checks 5" "gh pr list" "gh issue list" "gh issue view 3" "gh api repos/x/pulls" \
  "gh api repos/x/pulls --paginate" "gh api -X GET repos/x/pulls -f per_page=100" "gh api graphql -f query='{ viewer { login } }'" "gh -R o/r pr diff 5" \
  "gh pr diff 5 | head"; do
  allowed "$command" "$scratch"
  allowed "$command"
done
run_guard "$(payload "$agent" "$repository" "gh pr merge 5")"
assert_contains "$captured_output" 'gh pr merge'
assert_contains "$captured_output" 'GitHub'

# Words with $ : @ { } + stay whole: unquoted variables, URLs, refnames.
for command in "tmp=\$(mktemp -d); git init -q \$tmp" "git init \${tmp}/r" "git clone https://github.com/o/r.git \$tmp/c" \
  "git fetch https://github.com/o/r.git pull/5/head" "git fetch git@github.com:o/r.git main" "git tag --sort=-v:refname" \
  "git branch --merged origin/main@{u}" "git fetch origin pull/1/head --depth=1"; do
  allowed "$command"
done
blocked "git fetch https://github.com/o/r.git pull/5/head:pr5"
blocked "git fetch origin pull/\$N/head:pr\$N"
blocked "{ git checkout x; }"
blocked "echo \$(git checkout x)"
blocked "git config user.name x"
blocked "git config --file x user.name foo"
blocked "git config -f x user.name foo"
# init --separate-git-dir moves the repository's git dir; reflog and fsck can delete objects.
blocked "git init --separate-git-dir=\$tmp/gitdir"
blocked "git init --separate-git-dir \$tmp/gitdir"
blocked "git init --separate-git-dir=../elsewhere ."
blocked "git reflog expire --expire=now --all"
blocked "git reflog delete HEAD@{1}"
blocked "git fsck --lost-found"
allowed "git init --separate-git-dir=$scratch/gitdir" "$scratch"
# gh api: option values are not the endpoint; fields need an explicit GET to be a read.
allowed 'gh api -H "Accept: application/json" graphql -f query=q'
allowed "gh api --jq .x graphql -f query=q"
allowed "gh api --hostname github.com graphql -f query=q"
blocked 'gh api -H "Accept: application/json" repos/x/issues -f title=x'
run_guard "$(payload "$agent" "$repository" "gh api repos/x/issues -f title=x")"
assert_contains "$captured_output" '-X GET'

# 3. Throwaway work still runs.
allowed "git -C \"\$(mktemp -d)\" init && git -C \"\$(mktemp -d)\" commit --allow-empty -m x"
allowed "tmp=\$(mktemp -d) && cd \"\$tmp\" && git init -q && git commit -q --allow-empty -m x && git checkout -q -b y"
allowed "git init \"\$(mktemp -d)\""
allowed "git init -q -b main $scratch/new"
allowed "git clone -q $throwaway $scratch/copy"
allowed "cd $throwaway && git commit --allow-empty -m x"
allowed "cd $throwaway; git checkout -b y"
allowed "git -C $throwaway checkout -b z"
allowed "git commit --allow-empty -m x" "$throwaway"
allowed "bash -c 'cd $throwaway && git commit --allow-empty -m x'"
allowed "GIT_DIR=$throwaway/.git git checkout -b w"
allowed "cat > $scratch/script.sh <<'EOF'
git checkout main
git reset --hard
EOF
bash $scratch/script.sh"
allowed "python3 - <<'PY'
import subprocess
subprocess.run(['git', 'checkout', 'main'])
PY"
allowed "cat <<EOF | bash $scratch/script.sh
git commit -m x
EOF"
# A heredoc body is not commands, but the command after it still is.
blocked "cat > $scratch/script.sh <<'EOF'
git checkout main
EOF
git checkout main"
# Cannot tell where it runs: allowed, the house rule for anything unparseable.
allowed "cd \"\$dir\" && git checkout x"
allowed "cd - && git checkout x"
allowed "git -C \"\$dir\" checkout x"
allowed "git checkout 'unbalanced"
allowed "git checkout x" "$area/does-not-exist"

# 4. Loopholes: a subshell's cd ends with it; env and options that point back to the real repository.
blocked "(cd $throwaway && git commit --allow-empty -m x); git checkout y"
blocked "(cd $throwaway && git commit --allow-empty -m x) && git checkout y"
blocked "GIT_DIR=$repository/.git git checkout x" "$throwaway"
blocked "GIT_DIR=$repository/.git GIT_WORK_TREE=$repository git checkout x" "$throwaway"
blocked "export GIT_DIR=$repository/.git; git checkout x" "$throwaway"
blocked "env GIT_DIR=$repository/.git git checkout x" "$throwaway"
blocked "git --git-dir=$repository/.git checkout x" "$throwaway"
blocked "git --git-dir $repository/.git checkout x" "$throwaway"
blocked "GIT_WORK_TREE=$repository GIT_DIR=$throwaway/.git git checkout x" "$throwaway"
blocked "git --work-tree=$repository checkout x" "$throwaway"
blocked "git -C $repository checkout x" "$throwaway"
blocked "cd $repository && git checkout x" "$throwaway"
blocked "cd $throwaway; cd $repository; git checkout x" "$throwaway"
blocked "cd $worktree && git checkout x" "$throwaway"
blocked "cd $repository/.claude && git checkout x" "$throwaway"
blocked "cd $repository/not-yet-created && git checkout x" "$throwaway"
blocked "true && git checkout x"
blocked "if true; then git checkout x; fi"
blocked "bash -c 'git checkout x'"
blocked "sudo git checkout x"
blocked "command git checkout x"
blocked "/usr/bin/git checkout x"
allowed "cd $throwaway && bash -c 'git checkout x'; git status" "$repository"
blocked "git status && git checkout x"
blocked "git log | git checkout x"
blocked "echo \$(git checkout x)"

# 4b. Reads a reviewer needs are allowed; usage help never changes anything.
for command in "git check-ignore -v x" "git check-attr -a x" "git symbolic-ref HEAD" "git symbolic-ref --short HEAD" \
  "git submodule status" "git submodule" "git var GIT_AUTHOR_IDENT" "git notes show HEAD" "git notes list" \
  "git verify-commit HEAD" "git verify-tag v1" "git bundle verify x.bundle" "git bundle list-heads x.bundle" \
  "git hash-object README.md" "git merge-tree --write-tree main feature" "git check-ref-format refs/heads/x" \
  "git commit --help" "git push -h" "git reset --help" "gh pr merge --help" "gh pr review -h" "gh repo delete --help"; do
  allowed "$command"
done
# Help right after an option may be its value: not help, and the write still happens. After --, it is a path.
for command in "git commit --allow-empty -m -h" "git commit -m --help" "gh pr comment 5 --body -h" "gh pr review 5 -b --help"; do
  blocked "$command"
done
# Help after a positional is still help (git and gh read it anywhere); right after an option it may be its value.
for command in "gh pr merge 5 --help" "git push origin main --help" "gh repo deploy-key add k.pub -h"; do
  allowed "$command"
done
# The guard cannot tell a flag (-a) from an option that takes a value (-m), so help right after any option is refused.
blocked "git commit -a --help"
blocked "git reset -- a --help"
blocked "git clean -f -- x --help"
# git's own help option before the subcommand only shows the manual.
allowed "git --help commit"
allowed "git -h"
# ...and a write after it on the same line is still refused.
blocked "git --help && git push"
blocked "env git -h; git commit -am x"
for command in "git format-patch -1 --stdout" "git patch-id" "git tag -ln5" "git tag -n5 -l"; do
  allowed "$command"
done
blocked "git format-patch -1"
# ...but the writing forms of those commands are still refused.
for command in "git symbolic-ref HEAD refs/heads/other" "git symbolic-ref -d HEAD" "git submodule update --init" \
  "git notes add -m x" "git notes remove HEAD" "git hash-object -w README.md" "git bundle create x.bundle main"; do
  blocked "$command"
done

# 4c. gh commands that change GitHub, in any command group, are refused; reading ones are not.
for command in "gh issue delete 5 --yes" "gh repo delete o/r --yes" "gh pr lock 3" "gh pr unlock 3" "gh issue lock 4" \
  "gh issue pin 4" "gh issue transfer 4 o/other" "gh label create bug" "gh label delete bug" "gh secret set TOKEN" \
  "gh variable set X" "gh ssh-key add k.pub" "gh gist create f" "gh run cancel 9" "gh run rerun 9" "gh workflow run ci" \
  "gh release create v1" "gh release delete v1" "gh repo edit --visibility public" "gh repo archive o/r" \
  "gh alias set m 'pr merge'" "gh extension install o/gh-x" "gh auth logout" "gh cache delete 1"; do
  blocked "$command"
done
for command in "gh label clone o/other" "gh project item-add 1" "gh project item-delete 1" "gh project field-create 1" \
  "gh repo deploy-key add k.pub" "gh release delete-asset v1 a.zip" "gh repo set-default o/r" "gh auth setup-git" \
  "gh auth switch" "gh alias import a.yml" "gh codespace cp a b" "gh project link 1 --repo o/r" "gh project unlink 1" \
  "gh project copy 1" "gh project mark-template 1"; do
  blocked "$command"
done
for command in "gh project item-list 1 --owner o" "gh project field-list 1" "gh repo deploy-key list" \
  "gh repo deploy-key add --help" "gh repo clone o/r" "gh run view 9" "gh run list" "gh release list" "gh label list" "gh secret list" "gh repo view" \
  "gh auth status" "gh workflow list" "gh gist view 1" "gh issue view 4" "gh pr checks 3"; do
  allowed "$command"
done

# 5. Who is guarded: review-routing's agents, and the agents .claude/reviewers.toml names. Nothing else.
blocked "git checkout x" "$repository" "review-routing:change-reviewer"
blocked "git checkout x" "$repository" "review-routing:plugin-gate"
blocked "git checkout x" "$repository" "payments-reviewer"
blocked "git checkout x" "$repository" "someplugin:db-reviewer"
blocked "git checkout x" "$repository" "gatekeeper"
blocked "git checkout x" "$worktree" "gatekeeper"
blocked "git checkout x" "$repository/.claude" "gatekeeper"
# A user's own agents keep working, whatever their name or file says.
allowed "gh pr review 12 --approve" "$repository" "code-reviewer"
allowed "git checkout x" "$repository" "Payments-Reviewer"
allowed "git checkout x" "$repository" "someplugin:other-reviewer"
allowed "git checkout x" "$repository" "home-gate"
allowed "git commit -am x" "$repository" "marker-builder"
allowed "git checkout x" "$repository" "builder"
allowed "git checkout x" "$repository" "general-purpose"
allowed "git checkout x" "$repository" "other-plugin:builder"
allowed "git checkout x" "$repository" "unknown-agent"
allowed "git checkout x" "$repository" "other-plugin:plugin-gate"
allowed "git checkout x" "$repository" "../../etc/passwd"
allowed "git checkout x" "$repository" ""
allowed "gh pr merge 5" "$repository" "general-purpose"
# A built-in agent type the config names is not guarded: the same type also builds and commits in that session.
allowed "git commit -am wip" "$generic" "general-purpose"
allowed "git commit -am wip" "$generic" "Explore"
# A config name without an agent file of the project or the user is not guarded either.
printf '%s\n' 'default_reviewer = "ghost-reviewer"' > "$generic/.claude/reviewers.toml"
allowed "git commit -am wip" "$generic" "ghost-reviewer"
# A user-level agent (~/.claude/agents/) the config names is guarded.
printf '%s\n' 'default_reviewer = "home-gate"' > "$generic/.claude/reviewers.toml"
blocked "git commit -am wip" "$generic" "home-gate"
# This plugin's own agent is recognised even when agent_type arrives without the plugin prefix.
blocked "git checkout x" "$repository" "plugin-gate"
# An unreadable config guards nobody but review-routing's own agents.
allowed "git checkout x" "$broken" "gatekeeper"
blocked "git checkout x" "$broken" "review-routing:change-reviewer"
# No agent_type: a main-session call, never guarded, and the hook returns before it looks at anything.
run_guard "$(payload - "$repository" "git checkout x")"
assert_eq "$captured_exit_code" "0"
run_guard "$(payload - "$area/does-not-exist" "git checkout x")"
assert_eq "$captured_exit_code" "0"
run_guard '{"tool_name": "Bash", "tool_input": {"command": "git checkout x"}}'
assert_eq "$captured_exit_code" "0"
run_guard '{"tool_name": "Bash", "agent_type": null, "tool_input": {"command": "git checkout x"}}'
assert_eq "$captured_exit_code" "0"
fake_bin="$area/fake-bin"; mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\ntouch "%s/git-was-run"\nexit 1\n' "$area" > "$fake_bin/git"; chmod +x "$fake_bin/git"
run_capturing env PATH="$fake_bin:$PATH" TMPDIR="$scratch" python3 "$guard" <<< "$(payload - "$repository" "git checkout x")"
assert_eq "$captured_exit_code" "0"
[[ ! -e "$area/git-was-run" ]] || { echo "  git was started for a call with no agent_type"; exit 1; }
# A reviewer's call that needs no git decision does not start git either.
run_capturing env PATH="$fake_bin:$PATH" TMPDIR="$scratch" python3 "$guard" <<< "$(payload "$agent" "$repository" "ls -la && cat README.md")"
assert_eq "$captured_exit_code" "0"
[[ ! -e "$area/git-was-run" ]] || { echo "  git was started for a command that does not mention git"; exit 1; }

# Not a Bash call, unparseable input, wrong shapes: never get in the way.
run_guard '{"tool_name": "Read", "agent_type": "x-reviewer", "tool_input": {"file_path": "x"}}'
assert_eq "$captured_exit_code" "0"
run_guard 'not json'
assert_eq "$captured_exit_code" "0"
run_guard '{"tool_name": "Bash", "agent_type": "x-reviewer", "tool_input": {"command": 5}}'
assert_eq "$captured_exit_code" "0"
run_guard '{"tool_name": "Bash", "agent_type": 7, "tool_input": {"command": "git checkout x"}}'
assert_eq "$captured_exit_code" "0"
run_guard '[]'
assert_eq "$captured_exit_code" "0"
allowed "echo 'git checkout x'"
allowed "grep -rn 'git checkout' docs/"
allowed "git commit -m \"\$(cat <<'MSG'
docs: why we never run git checkout
MSG
)\"" "$throwaway"

# /tmp counts as temporary even when TMPDIR points elsewhere (the hook here sees $scratch as its temp dir).
other_temporary_repository="/tmp/reviewer-guard-test-$$"
trap 'rm -rf "$area" "$other_temporary_repository"' EXIT
git init --quiet -b main "$other_temporary_repository"
allowed "git -C $other_temporary_repository checkout -b y"
allowed "cd $other_temporary_repository && git commit --allow-empty -m x"

# Registered for Bash next to the Haiku guard, and the description names both.
python3 - "$hooks_json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
entries = {entry["matcher"]: entry for entry in data["hooks"]["PreToolUse"]}
assert set(entries) == {"Agent|Task", "Bash"}, entries.keys()
bash_hooks = entries["Bash"]["hooks"]
assert len(bash_hooks) == 1 and bash_hooks[0]["type"] == "command"
assert bash_hooks[0]["command"] == 'command -v python3 >/dev/null 2>&1 || exit 0; exec python3 "${CLAUDE_PLUGIN_ROOT}/hooks/reviewer-guard.py"', bash_hooks[0]["command"]
assert bash_hooks[0]["timeout"] == 10
assert "haiku-reviewer-guard" in data["description"] and "reviewer-guard" in data["description"].replace("haiku-reviewer-guard", "")
assert "haiku-reviewer-guard.py" in entries["Agent|Task"]["hooks"][0]["command"]
PY

# The reviewer prompts tell reviewers the read-only way, and say it is enforced by the hook.
# shellcheck disable=SC2016  # the single quotes are on purpose: the prompts contain a literal $(mktemp -d)
for file in plugins/review-routing/agents/change-reviewer.md plugins/review-routing/skills/add-reviewer/reviewer-template.md; do
  assert_contains "$(cat "$file")" 'git show <ref>:<path>'
  assert_contains "$(cat "$file")" 'git archive <ref> | tar -x -C "$(mktemp -d)"'
  assert_contains "$(cat "$file")" 'never check them out'
done
assert_contains "$(cat plugins/review-routing/skills/add-reviewer/reference.md)" 'git archive'
