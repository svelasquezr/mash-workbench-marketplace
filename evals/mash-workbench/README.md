# mash-workbench evals

Scenario cases for `claude plugin eval` against the `mash-workbench` plugin. They live outside `plugins/mash-workbench/` so that they do not ship with the plugin; `scripts/eval.sh mash-workbench` copies the plugin and these cases to a temporary folder and runs the eval there.

Each case builds a small git repository with its `setup.sh` and checks what a skill does with no user present, which is how `claude plugin eval` runs every case (`claude -p` in `dontAsk` mode). Every prompt says that nobody can answer. `Write` and `Edit` are granted, so a write that a regression makes lands and the `no-write`, `no-edit` and `file_exists` graders see it. The paths that need a user's answer (the first-time question, a written backlog line, a built candidate, an applied migration) cannot run here; check them by hand with `claude --plugin-dir plugins/mash-workbench`.

| Case                   | Skill   | Checks                                                                                           |
| ---------------------- | ------- | ------------------------------------------------------------------------------------------------ |
| 01-scout-no-user       | scout   | nothing written; the candidate is in the "Tooling candidates to record" block                    |
| 02-forge-no-user       | forge   | one table; duplicates merged; stale and undated entries flagged; nothing built                   |
| 03-forge-escape-topics | forge   | a mash-review topic with 3 files becomes a review-standard row; 1 file and `processed/` do not   |
| 04-migrate-no-user     | migrate | a proposal only; the old allow rule first; the location line; the review key stays               |
| 05-scout-old-settings  | scout   | with 0.x files, nothing written and the migrate hint                                             |
| 06-scout-old-default   | scout   | with only the 0.x default `docs/mash/tooling-backlog.md`, no second backlog and the migrate hint |

Run from the repository root (each case is a full Claude session on your credential):

```
bash scripts/eval.sh mash-workbench [--case '<glob>'] [other claude plugin eval options]
```

The script runs each case's `setup.sh` (`--scaffold`); read them first. They run only under `claude plugin eval`, never in a user's session. Results go to `evals/mash-workbench/results/`, which git ignores. The eval sandbox needs a host where `bwrap` can mount `/proc`; in a container without that permission every Bash call fails, and the skills then read files instead of running git.
