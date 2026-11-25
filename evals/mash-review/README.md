# mash-review evals

Scenario cases for `claude plugin eval` against the `mash-review` plugin. They live outside `plugins/mash-review/` so that they do not ship with the plugin: the eval tool needs them inside the plugin folder, so `scripts/eval.sh mash-review` copies the plugin and these cases to a temporary folder and runs the eval there.

Each case builds a small git repository with its `setup.sh` and checks what the skills do with no user present, which is how `claude plugin eval` runs every case (`claude -p` in `dontAsk` mode). Cases 01 to 06, 08 and 09 also say in the prompt that nobody can answer; case 07 does not, to show that a session started from one prompt does not stop at a question. Cases 01, 02, 08 and 09 grade the `model` passed to the reviewer: `opus` with no standard (01) and in a group where one standard has no `Model:` line (08), `sonnet` when every standard says `Model: sonnet` (02) or the request names it (09). No grader checks that the reviewer ran `git diff` itself: in a sandbox where Bash fails the reviewer reads files instead, and the reviewer's own tool calls are not graded. The case sessions load user settings only (`--setting-sources user`), so they may find the project's standards and `CLAUDE.md` by reading the files rather than the way a normal session lists them; check standard selection in a normal session by hand too. `Write` and `Edit` are granted, so a write that a regression makes lands and the `no-write`, `no-edit` and `file_exists` graders see it. Plan mode and the paths that need a user's answer (an escape written into a standard or a file, `add-standard`, an applied migration) cannot run here; check them by hand with `claude --plugin-dir plugins/mash-review`.

Run from the repository root (each case is a full Claude session on your credential; the runs on 2026-11-23 cost $0.13 to $0.29 a case):

```
bash scripts/eval.sh mash-review [--case '<glob>'] [other claude plugin eval options]
```

The script runs each case's `setup.sh` (`--scaffold`); read them first. They run only under `claude plugin eval`, never in a user's session. The eval sandbox gives git a throwaway `HOME` with its own identity and no system config, so the setups need no `git -c` options. Results go to `evals/mash-review/results/`, which git ignores. The eval sandbox needs a host where `bwrap` can mount `/proc`; in a container without that permission every Bash call fails, and case 04 (which runs `bash check.sh`) fails there.
