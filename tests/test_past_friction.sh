# shellcheck shell=bash
# mash-workbench's past-friction.py reads a project's Claude Code transcripts and prints corrections and Bash command
# sequences that recur in 2 or more sessions. It is read-only and prints dates and counts, not whole transcripts.
set -euo pipefail
source tests/lib.sh
script=plugins/mash-workbench/scripts/past-friction.py
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT
projects="$temporary_directory/projects"
project_path=/work/my.repo
slug=-work-my-repo
mkdir -p "$projects/$slug" "$projects/$slug--claude-worktrees-feature" "$projects/-work-my-repo-other"

# session <file> <date> <prompt|cmd:...>...: writes a transcript with one user prompt or Bash call per argument.
session() {
  python3 - "$@" <<'PY'
import json, sys
path, date, *items = sys.argv[1:]
with open(path, "w") as out:
    for i, item in enumerate(items):
        stamp = f"{date}T10:{i:02d}:00.000Z"
        if item.startswith("cmd:"):
            content = [{"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": item[4:]}}]
            out.write(json.dumps({"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": content}}) + "\n")
        else:
            out.write(json.dumps({"type": "user", "timestamp": stamp, "message": {"role": "user", "content": item}}) + "\n")
    out.write("not json\n")
PY
}
session "$projects/$slug/a.jsonl" 2026-10-10 "No, never amend commits on the review branch" "cmd:git fetch origin" \
  "cmd:git merge origin/main --no-edit" "cmd:bash tests/run.sh"
session "$projects/$slug--claude-worktrees-feature/b.jsonl" 2026-10-15 "I told you: never amend commits on a review branch" \
  "cmd:git fetch origin main" "cmd:git merge --no-ff origin/main" "cmd:bash tests/run.sh 2>&1"
session "$projects/$slug/c.jsonl" 2026-10-16 "add another test" "cmd:ls" "cmd:git status"
# Another project with the same corrections and commands: ignored.
session "$projects/-work-my-repo-other/d.jsonl" 2026-10-16 "Don't amend commits on the review branch" \
  "cmd:git fetch origin" "cmd:git merge origin/main" "cmd:bash tests/run.sh"
# Too old for the default window.
session "$projects/$slug/e.jsonl" 2026-09-01 "No, stop using sed for edits" "cmd:true"
session "$projects/$slug/f.jsonl" 2026-10-17 "stop using sed for edits, please" "cmd:true"
# A subagent's prompt and a tool result are not the user's words.
printf '%s\n' '{"type":"user","isSidechain":true,"timestamp":"2026-10-17T10:00:00Z","message":{"content":"Do not use sed for edits"}}' \
  '{"type":"user","timestamp":"2026-10-17T10:00:00Z","message":{"content":[{"type":"tool_result","content":"stop using sed for edits"}]}}' \
  >> "$projects/$slug/c.jsonl"
# Nor are a peer agent's message, an SDK prompt or an injected notice, even when they read as corrections.
printf '%s\n' '{"type":"user","origin":{"kind":"peer"},"timestamp":"2026-09-01T11:00:00Z","message":{"content":"Do not use sed for edits"}}' \
  '{"type":"user","promptSource":"sdk","timestamp":"2026-09-01T11:00:00Z","message":{"content":"Do not use sed for edits"}}' \
  '{"type":"user","timestamp":"2026-09-01T11:00:00Z","message":{"content":"<task-notification>stop using sed</task-notification>"}}' \
  >> "$projects/$slug/e.jsonl"

before=$(find "$projects" -type f -exec cksum {} + | sort)
output=$(python3 "$script" --project "$project_path" --projects-dir "$projects" --today 2026-10-21)
assert_eq "$(find "$projects" -type f -exec cksum {} + | sort)" "$before"
assert_contains "$output" "correction · 2 sessions (2026-10-10, 2026-10-15) · "
assert_contains "$output" "amend commits"
assert_contains "$output" "sequence · 2 sessions (2026-10-10, 2026-10-15) · git fetch → git merge → bash run.sh"
assert_not_contains "$output" "sed for edits"
assert_not_contains "$output" "git status"
# Browsing commands (cd, ls, cat, ...) are left out of sequences; arguments after the subcommand or script are cut.
assert_not_contains "$output" "ls →"
assert_eq "$(grep -c '^correction' <<< "$output")" "1"

# A wider window reaches the September session, so the sed correction now spans 2 sessions.
output=$(python3 "$script" --project "$project_path" --projects-dir "$projects" --today 2026-10-21 --days 60)
assert_contains "$output" "correction · 2 sessions (2026-09-01, 2026-10-17) · "

# No transcripts: a note, exit 0.
run_capturing python3 "$script" --project /nowhere --projects-dir "$projects"
assert_eq "$captured_exit_code" "0"
assert_contains "$captured_output" "no transcripts"

# --- Filters and edge cases (fix round 1) ---
second="$temporary_directory/second"; projects2="$second/projects"; mkdir -p "$projects2/$slug"
# entry <file> <json fields...>: appends one transcript line built from key=json pairs.
entry() { python3 -c 'import json, sys; print(json.dumps({k: json.loads(v) for k, v in (a.split("=", 1) for a in sys.argv[2:])}))' "$@" >> "$1"; }
bash_call() { entry "$1" type='"assistant"' uuid="\"$2\"" timestamp="\"$3T10:00:00Z\"" \
  message="{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$4")}}]}"; }
typed() { entry "$1" type='"user"' uuid="\"$2\"" timestamp="\"$3T10:00:00Z\"" "${@:5}" message="{\"content\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$4")}"; }
for s in one two; do
  f="$projects2/$slug/$s.jsonl"; day=$([[ $s == one ]] && echo 2026-10-12 || echo 2026-10-14)
  bash_call "$f" "$s-1" "$day" "cd /repo && timeout 60 git fetch origin"
  bash_call "$f" "$s-2" "$day" "ls -la"
  bash_call "$f" "$s-3" "$day" "git -C /home/me/secret-path merge origin/main"
  bash_call "$f" "$s-4" "$day" "bash -c \"curl -H 'Authorization: Bearer sk-live-XYZ' https://x\""
  bash_call "$f" "$s-5" "$day" "bash /home/me/.cache/tools/1.2.3/ship.sh --merge"
  # A typed correction by a human origin counts; hook feedback, local command output, meta, system and long ones don't.
  typed "$f" "$s-6" "$day" "don't use sed for edits" origin='{"kind":"human"}'
  typed "$f" "$s-7" "$day" "Stop hook feedback: don't use pip here" isMeta=true
  typed "$f" "$s-8" "$day" "<local-command-stdout>don't use pip here</local-command-stdout>"
  typed "$f" "$s-12" "$day" "<bash-stdout>don't use pip here</bash-stdout>"
  typed "$f" "$s-9" "$day" "don't use pip here" promptSource='"system"'
  typed "$f" "$s-10" "$day" "don't use pip here" entrypoint='"sdk-cli"'
  typed "$f" "$s-11" "$day" "don't use pip here $(printf 'x%.0s' {1..500})"
done
# A resumed session copies earlier messages (same uuids) into a new file: they count once.
typed "$projects2/$slug/three.jsonl" "x-1" 2026-10-15 "I said never force push to main"
cp "$projects2/$slug/three.jsonl" "$projects2/$slug/three-resumed.jsonl"
bash_call "$projects2/$slug/three-resumed.jsonl" "x-2" 2026-10-16 "true"

output=$(cd "$second" && python3 "$OLDPWD/$script" --project "$project_path" --projects-dir projects --today 2026-10-21)
assert_contains "$output" "sequence · 2 sessions (2026-10-12, 2026-10-14) · git fetch → git merge → bash"
assert_contains "$output" "git merge → bash → bash ship.sh"
assert_not_contains "$output" "secret-path"
assert_not_contains "$output" "sk-live"
assert_not_contains "$output" "/home/me"
assert_not_contains "$output" "ls"
assert_contains "$output" 'correction · 2 sessions (2026-10-12, 2026-10-14) · "don'"'"'t use sed for edits"'
assert_not_contains "$output" "pip"
assert_not_contains "$output" "force push"
# A relative --project is resolved.
mkdir -p "$second/work/my.repo"
resolved_slug=$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9-]", "-", sys.argv[1]))' "$(cd "$second/work/my.repo" && pwd -P)")
cp -r "$projects2/$slug" "$projects2/$resolved_slug"
output=$(cd "$second/work" && python3 "$OLDPWD/$script" --project my.repo --projects-dir "$projects2" --today 2026-10-21)
assert_contains "$output" "git fetch → git merge"

# short_command never prints a quoted fragment, inline code, an option's value or a path (fix round 2 cases).
shortened=$(python3 - "$script" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("past_friction", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
cases = [
    'grep -E "password|sk-live-XYZ" .env', 'grep -rn "foo\\|bar" src', 'ls; bash -lc "export TOKEN=abc && run"',
    'bash -lc "echo sk-live-XYZ"', 'node -pe "process.env.TOKEN"', 'python3 -Sc "print(1)"',
    'git --git-dir /secret/repo status', 'kubectl --kubeconfig /home/me/.kube/cfg get pods', 'claude "fix with token abc"',
    'timeout --signal KILL 60 git fetch', 'sudo -u bob docker ps', 'env -u FOO git status', 'git -c user.name=x commit -m "wip"',
    'cd /repo && bash tests/run.sh 2>&1 | tail -5',
    'node --eval "process.env.TOKEN"', 'node --print process.version', 'if git diff --quiet; then echo x; fi',
    'pnpm --filter web build', 'for pr in 12 13; do gh pr view $pr; done', 'git add a b && git commit -m "$(cat <<EOF', 'gh pr create --title x \\', 'python3 - <<EOF', "echo 'unclosed", 'FOO=1 uv run pytest -q',
]
for case in cases:
    print(f"{case} => [{module.short_command(case)}]")
PY
)
# shellcheck disable=SC2016  # literal commands, nothing to expand
expected='grep -E "password|sk-live-XYZ" .env => []
grep -rn "foo\|bar" src => []
ls; bash -lc "export TOKEN=abc && run" => [bash]
bash -lc "echo sk-live-XYZ" => [bash]
node -pe "process.env.TOKEN" => [node]
python3 -Sc "print(1)" => [python3]
git --git-dir /secret/repo status => [git status]
kubectl --kubeconfig /home/me/.kube/cfg get pods => [kubectl get]
claude "fix with token abc" => [claude]
timeout --signal KILL 60 git fetch => [git fetch]
sudo -u bob docker ps => [docker ps]
env -u FOO git status => [git status]
git -c user.name=x commit -m "wip" => [git commit]
cd /repo && bash tests/run.sh 2>&1 | tail -5 => [bash run.sh]
node --eval "process.env.TOKEN" => [node]
node --print process.version => [node]
if git diff --quiet; then echo x; fi => [git diff]
pnpm --filter web build => [pnpm build]
for pr in 12 13; do gh pr view $pr; done => [gh pr]
git add a b && git commit -m "$(cat <<EOF => [git add]
gh pr create --title x \ => [gh pr]
python3 - <<EOF => [python3]
echo '"'"'unclosed => []
FOO=1 uv run pytest -q => [uv run]'
assert_eq "$shortened" "$expected"

# The correction phrase list: these read as corrections, the near misses below do not.
matches() {
  python3 -I - "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("past_friction", "plugins/mash-workbench/scripts/past-friction.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print("yes" if module.CORRECTION.search(sys.argv[1]) else "no")
PY
}
for prompt in "No, use the script instead" "I said to run the full suite" "I told you not to amend commits" \
  "stop doing that" "Don't add comments to every line" "do not use sed for this" "that's wrong, the base is main" \
  "You forgot the version bump again" "again you left the test out" "same mistake as before" "you keep pushing to main" \
  "As I mentioned, tests come first" "Don’t use sed" "that’s wrong" "you did it again" "Please don't touch main"; do
  assert_eq "$(matches "$prompt")" "yes"
done
for prompt in "I know the answer" "add another test" "run the tests again" "Nothing changed" "No tests for docs-only changes" \
  "Notice the stale entries" ""; do
  assert_eq "$(matches "$prompt")" "no"
done

# --- privacy: only wording that repeats across sessions is printed ---------------------------------------------------
secrets="$temporary_directory/secrets"; mkdir -p "$secrets/projects/$slug"
session "$secrets/projects/$slug/s1.jsonl" 2026-10-18 "No, don't use the token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 again, curl is wrong"
session "$secrets/projects/$slug/s2.jsonl" 2026-10-19 "No, don't use the password Hunter2Secret again, curl is wrong"
output=$(python3 "$script" --project "$project_path" --projects-dir "$secrets/projects" --today 2026-10-21)
assert_contains "$output" "correction · 2 sessions"
assert_contains "$output" "curl is wrong"
assert_not_contains "$output" "ghp_"
assert_not_contains "$output" "Hunter2Secret"
assert_not_contains "$output" "token"
assert_not_contains "$output" "password"

# A transcript that is a symlink to a file outside the projects folder is not read.
linked="$temporary_directory/linked"; mkdir -p "$linked/projects/$slug" "$linked/outside"
session "$linked/projects/$slug/real.jsonl" 2026-10-18 "No, never amend commits on the review branch"
session "$linked/outside/other.jsonl" 2026-10-19 "No, never amend commits on the review branch"
ln -s "$linked/outside/other.jsonl" "$linked/projects/$slug/link.jsonl"
output=$(python3 "$script" --project "$project_path" --projects-dir "$linked/projects" --today 2026-10-21)
assert_not_contains "$output" "correction ·"

# CLAUDE_CONFIG_DIR moves the default projects folder.
config_home="$temporary_directory/config-home"; mkdir -p "$config_home"; cp -R "$projects" "$config_home/projects"
output=$(CLAUDE_CONFIG_DIR="$config_home" python3 "$script" --project "$project_path" --today 2026-10-21)
assert_contains "$output" "correction · 2 sessions (2026-10-10, 2026-10-15) · "
