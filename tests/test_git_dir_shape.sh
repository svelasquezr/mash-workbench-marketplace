# shellcheck shell=bash
# A commit can hold a folder shaped like a git directory (HEAD plus objects/ and refs/, or a commondir file); only the
# name .git cannot be committed. Git accepts such a folder as a repository, and its committed config then chooses
# core.worktree (a fake top level) and core.fsmonitor (a program git runs when it reads an index). The scripts must
# never start git in such a folder: no committed program runs, and no committed file chooses a place outside the
# repository. Each case plants a program that leaves a marker file, and checks that the marker never appears.
set -euo pipefail
source tests/lib.sh
source tests/git_fixtures.sh
mw="$PWD/plugins/mash-workbench"
settings_script="$mw/scripts/mash-settings.sh"
area=$(mktemp -d "$HOME/.git-dir-shape-test.XXXXXX"); trap 'rm -rf "$area"' EXIT
case "$(cd "$area" && pwd -P)" in /tmp/* | /var/tmp/*) echo "  HOME is under /tmp: the fixture cannot hold a non-temporary repository"; exit 1 ;; esac
temporary_directory="$area"
isolate_git_config
unset REVIEW_ROUTING_ESCAPES MASH_WORKBENCH_BACKLOG
settings() { bash "$settings_script" "$@"; }
new_repository() { git init --quiet "$1"; git -C "$1" commit --quiet --allow-empty -m "chore: base"; }
marker="$area/payload-ran"
payload="$area/payload.sh"
printf '#!/bin/sh\ntouch "%s"\n' "$marker" > "$payload"; chmod +x "$payload"
no_marker() { if [[ -e "$marker" ]]; then echo "  the planted program ran ($1)"; exit 1; fi; }
# plant_git_dir <folder> <core.worktree or ""> [commondir|linkhead]: the git-directory shape, with a config that names
# the payload as fsmonitor program, hooks folder and promisor remote (a lazy fetch runs uploadpack: no index needed).
# linkhead: HEAD is a dangling symbolic link to refs/heads/x, which git accepts and [[ -e ]] does not see.
plant_git_dir() {
  mkdir -p "$1"
  if [[ "${3:-}" == linkhead ]]; then ln -s refs/heads/x "$1/HEAD"; else printf 'ref: refs/heads/main\n' > "$1/HEAD"; fi
  if [[ "${3:-}" == commondir ]]; then
    printf '../../.git\n' > "$1/commondir"
  else
    mkdir -p "$1/objects" "$1/refs"; touch "$1/objects/keep" "$1/refs/keep"
  fi
  {
    printf '[core]\n\trepositoryformatversion = 1\n\tfsmonitor = %s\n\thooksPath = %s\n' "$payload" "$area/hooks"
    if [[ -n "$2" ]]; then printf '\tbare = false\n\tworktree = %s\n' "$2"; else printf '\tbare = true\n'; fi
    printf '[extensions]\n\tpartialClone = origin\n[remote "origin"]\n\turl = .\n\tpromisor = true\n\tuploadpack = %s\n' "$payload"
    printf '[protocol "file"]\n\tallow = always\n'
  } > "$1/config"
}
mkdir -p "$area/hooks"; for hook in post-checkout post-index-change reference-transaction; do cp "$payload" "$area/hooks/$hook"; done

# 1. C-1: the home folder .claude/mash-workbench is shaped like a git directory whose core.worktree is the main
#    worktree, and the repository commits settings.local there. The file is committed, so it is not the user's.
one="$area/one"; new_repository "$one"
plant_git_dir "$one/.claude/mash-workbench" ../..
printf 'escapes=../victim-1/.claude/rules\nbacklog=../victim-1/notes.md\nescapes.threshold=1\n' > "$one/.claude/mash-workbench/settings.local"
git -C "$one" add -f .claude; git -C "$one" commit --quiet -m "chore: a home folder shaped like a git directory"
git clone --quiet "$one" "$area/one-clone"
clone="$area/one-clone"
assert_eq "$(settings source "$clone" escapes)" "team"
no_marker "source"
run_capturing settings path "$clone" escapes
assert_eq "$captured_exit_code" "6"
run_capturing settings set "$clone" escapes.threshold 4 --local
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git rm --cached"
assert_eq "$(git -C "$clone" status --porcelain)" ""
run_capturing bash "$in_root_script" "$mw/skills/scout/backlog-add.sh" "$clone" script "A title" "why"
assert_eq "$captured_exit_code" "6"
no_marker "C-1 scripts"
[[ ! -e "$area/victim-1" ]] || { echo "  a script wrote outside the repository"; exit 1; }

# The same with .claude itself shaped like a git directory (core.worktree = ..).
two="$area/two"; new_repository "$two"
plant_git_dir "$two/.claude" ..
mkdir -p "$two/.claude/mash-workbench"
printf 'escapes=../victim-2/.claude/rules\nbacklog=../victim-2/notes.md\n' > "$two/.claude/mash-workbench/settings.local"
git -C "$two" add -f .claude; git -C "$two" commit --quiet -m "chore: .claude shaped like a git directory"
git clone --quiet "$two" "$area/two-clone"
assert_eq "$(settings source "$area/two-clone" escapes)" "team"
run_capturing settings path "$area/two-clone" escapes
assert_eq "$captured_exit_code" "6"
run_capturing bash "$in_root_script" "$mw/skills/scout/backlog-add.sh" "$area/two-clone" script "A title" "why"
assert_eq "$captured_exit_code" "6"
no_marker "C-1, .claude"
[[ ! -e "$area/victim-2" ]] || { echo "  a script wrote outside the repository"; exit 1; }

# 2. C-2: a <repo-root> (a prompt can choose it) that names a committed folder shaped like a git directory. Every
#    command refuses it with exit 6, starts no git there, and writes nothing.
three="$area/three"; new_repository "$three"
plant_git_dir "$three/tools/cache" wt
mkdir -p "$three/tools/cache/wt/.claude/mash-workbench"
printf 'escapes=../../../../victim-3/.claude/rules\nbacklog=../../../../victim-3/notes.md\n' > "$three/tools/cache/wt/.claude/mash-workbench/settings.local"
plant_git_dir "$three/tools/bare" ""
plant_git_dir "$three/tools/root" ../..
plant_git_dir "$three/tools/common" .. commondir
plant_git_dir "$three/tools/linkhead" ""  linkhead
mkdir -p "$three/tools/linkhead/deep/er"; touch "$three/tools/linkhead/deep/er/keep"
git -C "$three" add -f tools; git -C "$three" commit --quiet -m "chore: folders shaped like git directories"
git clone --quiet "$three" "$area/three-clone"
for fake in tools/cache tools/cache/wt tools/bare tools/root tools/common tools/cache/objects tools/linkhead tools/linkhead/deep/er; do
  root="$area/three-clone/$fake"
  for arguments in "main-worktree $root" "home $root" "toplevel $root" "get $root escapes" "source $root escapes" "path $root escapes" \
    "set $root escapes.threshold 4 --local" "check-escapes-path $root /x" "repo-key $root"; do
    # shellcheck disable=SC2086  # the words are split on purpose
    run_capturing settings $arguments
    assert_eq "$captured_exit_code" "6"
    assert_contains "$captured_output" "shaped like a git directory"
  done
  run_capturing bash "$mw/skills/scout/permission-rules.sh" "$root"
  assert_eq "$captured_exit_code" "6"
  run_capturing bash "$mw/skills/scout/backlog-path.sh" "$root"
  assert_eq "$captured_exit_code" "6"
  run_capturing bash "$in_root_script" "$mw/skills/scout/backlog-add.sh" "$root" script "A title" "why"
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "shaped like a git directory"
  no_marker "C-2, $fake"
done
[[ ! -e "$area/victim-3" ]] || { echo "  a script wrote outside the repository"; exit 1; }
# The environment variable is the user's own: it still answers get, and path still refuses the fake repository.
assert_eq "$(REVIEW_ROUTING_ESCAPES="$area/env-escapes" settings get "$area/three-clone/tools/cache" escapes)" "$area/env-escapes"
run_capturing env REVIEW_ROUTING_ESCAPES="$area/env-escapes" bash "$settings_script" path "$area/three-clone/tools/cache" escapes
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "shaped like a git directory"

# 3. A .git entry that git does not take (an empty folder) makes git answer from the folder above: refused, since the
#    repository git found is not the one the .git entry names.
mkdir -p "$area/three-clone/sub/.git"
run_capturing settings main-worktree "$area/three-clone/sub"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git cannot use"
# A .git folder that holds only HEAD: git skips it too, so the walk refuses it before git reads the folders above.
printf 'ref: refs/heads/main\n' > "$area/three-clone/sub/.git/HEAD"
run_capturing settings main-worktree "$area/three-clone/sub"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git cannot use"
assert_not_contains "$captured_output" "not the one that"
# objects and refs but no HEAD: refused by the walk as well.
rm "$area/three-clone/sub/.git/HEAD"; mkdir -p "$area/three-clone/sub/.git/objects" "$area/three-clone/sub/.git/refs"
run_capturing settings main-worktree "$area/three-clone/sub"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git cannot use"
rm -r "$area/three-clone/sub"
# The same in a bare repository, where git's answer has no top level to compare: the git dir git took is checked too.
git clone --quiet --bare "$one" "$area/bare.git"
# The .git folder has the full shape, but git rejects its HEAD, so git takes the bare repository above it.
mkdir -p "$area/bare.git/sub/.git/objects" "$area/bare.git/sub/.git/refs"; printf 'not a ref\n' > "$area/bare.git/sub/.git/HEAD"
run_capturing settings main-worktree "$area/bare.git/sub"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "not the one that"

# 4. A submodule or a nested repository at the home folder: its files are not this clone's own.
nested="$area/nested"; new_repository "$nested"; git init --quiet "$nested/.claude/mash-workbench"
printf 'escapes=../victim-4\n' > "$nested/.claude/mash-workbench/settings.local"
for arguments in "source $nested escapes" "home $nested" "set $nested escapes.threshold 4 --local"; do
  # shellcheck disable=SC2086
  run_capturing settings $arguments
  assert_eq "$captured_exit_code" "6"
  assert_contains "$captured_output" "nested repository"
done
nested_claude="$area/nested-claude"; new_repository "$nested_claude"; git init --quiet "$nested_claude/.claude"
run_capturing settings home "$nested_claude"
assert_eq "$captured_exit_code" "6"

# 5. Git cannot answer (a damaged index): the file is read as committed, and set --local says why it refuses.
broken="$area/broken"; new_repository "$broken"; mkdir -p "$broken/.claude/mash-workbench"
printf 'escapes=../outside\n' > "$broken/.claude/mash-workbench/settings.local"
git -C "$broken" add -f .claude/mash-workbench/settings.local; git -C "$broken" commit --quiet -m "chore: local"
printf 'not an index' > "$broken/.git/index"
assert_eq "$(settings source "$broken" escapes)" "team"
run_capturing settings set "$broken" escapes.threshold 4 --local
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "could not tell"
# The same damaged index with an untracked file: still not "private", because git gave no answer.
git -C "$broken" rm --quiet --cached .claude/mash-workbench/settings.local 2>/dev/null || true
printf 'not an index' > "$broken/.git/index"
assert_eq "$(settings source "$broken" escapes)" "team"

# 6. GIT_DIR in the environment (a git hook sets it) does not change the answer for the user's own private file.
own="$area/own"; new_repository "$own"
settings set "$own" escapes ../own-outside --local >/dev/null
assert_eq "$(cd "$own" && GIT_DIR=.git bash "$settings_script" source "$own" escapes)" "local"
assert_eq "$(GIT_DIR="$own/.git" bash "$settings_script" source "$own" escapes)" "local"
assert_eq "$(GIT_DIR="$three/.git" GIT_WORK_TREE="$three" bash "$settings_script" main-worktree "$own")" "$(cd "$own" && pwd -P)"
# Neither do GIT_COMMON_DIR or config given in the environment (GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT).
assert_eq "$(GIT_COMMON_DIR="$three/.git" bash "$settings_script" main-worktree "$own")" "$(cd "$own" && pwd -P)"
assert_eq "$(GIT_CONFIG_PARAMETERS="'core.worktree'='$three'" bash "$settings_script" main-worktree "$own")" "$(cd "$own" && pwd -P)"
assert_eq "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$three" bash "$settings_script" main-worktree "$own")" "$(cd "$own" && pwd -P)"
# 7. The second guard: git runs with an empty core.fsmonitor, so even a configured program (here in the repository's
#    own config) does not run when the scripts read the index.
git -C "$own" add -f .claude/mash-workbench/settings.local
git -C "$own" config core.fsmonitor "$payload"
assert_eq "$(settings source "$own" escapes)" "team"
run_capturing settings check-escapes-path "$own" .claude/mash-workbench/escapes
# 10. Opus review I-3: source answers from the environment variable, as get does (the header names both).
assert_eq "$(REVIEW_ROUTING_ESCAPES="$area/env-escapes" settings source "$area/three-clone/tools/cache" escapes)" "env"

# 11. Opus review M-1: an untracked settings.local counts as the user's own only when the exclude line that set --local
#     writes is in the git directory (a patch applied with git apply cannot write there).
patched="$area/patched"; new_repository "$patched"; mkdir -p "$patched/.claude/mash-workbench"
printf 'escapes=../patched-outside\n' > "$patched/.claude/mash-workbench/settings.local"
assert_eq "$(settings source "$patched" escapes)" "team"
run_capturing settings path "$patched" escapes
assert_eq "$captured_exit_code" "6"
settings set "$patched" escapes.threshold 3 --local >/dev/null
assert_eq "$(settings source "$patched" escapes)" "local"

# 12. Opus review M-3: a .git entry that git cannot use (an empty folder) is refused by the walk itself, before git
#     goes on to the folders above.
mkdir -p "$area/three-clone/sub2/.git"
run_capturing settings main-worktree "$area/three-clone/sub2"
assert_eq "$captured_exit_code" "6"
assert_contains "$captured_output" "git cannot use"
rm -r "$area/three-clone/sub2"

# 13. A --separate-git-dir repository whose git folder is named .git: nothing records the work folder, so every
#     worktree gives git's own answer (the git folder's parent, as git worktree list does), and the settings never
#     split between two home folders.
mkdir -p "$area/store/proj"
git init --quiet --separate-git-dir "$area/store/proj/.git" "$area/work/proj"
printf 'a\n' > "$area/work/proj/a"; git -C "$area/work/proj" add a; git -C "$area/work/proj" commit --quiet -m "feat: a"
git -C "$area/work/proj" worktree add --quiet "$area/work/proj/.claude/worktrees/w1" -b w1
assert_eq "$(settings main-worktree "$area/work/proj")" "$(cd "$area/store/proj" && pwd -P)"
assert_eq "$(settings main-worktree "$area/work/proj/.claude/worktrees/w1")" "$(cd "$area/store/proj" && pwd -P)"

# 14. A linked worktree finds its main worktree whatever the main worktree holds on disk: sparse checkout, only
#     non-ASCII names, the first files deleted (the second Opus review found these broken by a guess from the index).
for kind in sparse unicode deleted; do
  repo="$area/near-$kind"; git init --quiet "$repo"
  if [[ "$kind" == unicode ]]; then
    for n in 1 2 3; do printf 'x\n' > "$repo/données-$n.md"; done
  else
    mkdir -p "$repo/.github/workflows" "$repo/src"
    for n in $(seq 1 25); do printf 'x\n' > "$repo/.github/workflows/w$n.yml"; done
    printf 'x\n' > "$repo/src/main.sh"
  fi
  git -C "$repo" add -A; git -C "$repo" commit --quiet -m "feat: files"
  case "$kind" in
    sparse) git -C "$repo" sparse-checkout set --cone src ;;
    deleted) rm -r "$repo/.github" ;;
  esac
  git -C "$repo" worktree add --quiet "$repo/.claude/worktrees/w1" -b w1
  assert_eq "$(settings main-worktree "$repo/.claude/worktrees/w1")" "$(cd "$repo" && pwd -P)"
done
no_marker "end"
echo "git-dir shape: ok"
