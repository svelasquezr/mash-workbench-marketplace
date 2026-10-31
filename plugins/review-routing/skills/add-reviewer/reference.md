# add-reviewer reference

Detail the add-reviewer skill points to. `reviewers.example.toml` shows the keys in use; this lists every key.

## Config keys (`.claude/reviewers.toml`)

| Key | Meaning |
|---|---|
| `default_reviewer` | who reviews a path nothing else claims (default `review-routing:change-reviewer`, this plugin's read-only Sonnet reviewer) |
| `allow_default` | tracked paths that may get only the default reviewer: regexes, or `{ pattern, reason }` tables; enables the coverage check |
| `[[routes]]` `pattern`, `reviewers`, `reason` | a path matching `pattern` gets every listed reviewer; all matching routes apply |
| `[[mirrors]]` `pattern`, `source`, `shorter_names` | a test also counts as the code `source` names (`\g<group>` from `pattern`); the first match is used |
| `[[changed_lines]]` `path_pattern`, `line_pattern`, `reviewers`, `reason` | a changed line (added or removed) matching `line_pattern` in a matching file adds reviewers (a PR file without a patch adds them too). The pattern sees the line without its `+`/`-`, so `^` anchors at its content; rewrite a pattern such as `^\+foo` as `^foo` (added and removed lines can no longer be told apart) |
| `[[fallbacks]]` `pattern`, `reviewers`, `reason` | only for a path no route claims; the first match wins |
| `default_model` | the model the default reviewer runs on in this project: sonnet, opus or fable (the models a reviewer can be started on); the review-changes skill passes it when it starts the agent |
| `[[model_rules]]` `reviewer`, `model`, `title_pattern`, `path_pattern`, `min_added_lines`, `reason` | run `reviewer` on `model` (sonnet, opus or fable) when every condition given holds: the title matches (the PR title; for a range, any of its commit subjects; `--title` for a preview), a changed path matches, at least that many lines were added under `path_pattern` (a range preview counts a moved file's lines as added; the pull request counts only edited ones). The first matching rule wins; else `default_model` (default reviewer only), else the agent file's `model:` |
| `[[import_guards]]` `name`, `language`, `source_dirs`, `entry_modules`, `reviewer`, `allow` | every project file the entry modules import, transitively (parent packages and relative imports included; Python only), must be routed to `reviewer` or listed in `allow` as `{ path or pattern, reason }`; `--check` fails on an unreviewed file, a stale allow entry, a missing entry module or a file it can't parse; star and dynamic imports are not followed |
| `[[expect]]` `path`, `reviewers` | a routing test case for `--check`: the exact set of reviewers `path` gets |

`reason` (optional) says why, in a few words; `route --explain` prints it next to the rule. Patterns are Python regular expressions searched in repository-relative paths; anchor with `^`, escape dots, and use TOML literal strings (`'...'`) so backslashes stay as written. Top-level keys go before the first `[[table]]`.

## As the reviewers grow

- A rule several agent files repeat moves into a convention test in the project (for example: every `.claude/agents/*-reviewer.md` contains the judge-only sentence and the verdict line, and none declares a `haiku` model).
- Agents that build and commit run one at a time; reviewers and research agents (read-only) may run in parallel.
- `route --check` looks for each reviewer's agent file in the project's `.claude/agents/` only, not in `~/.claude/agents/`.
- Keep reviews cheap: reviewers get the check results instead of running checks, and a fix round goes only to the reviewers the review-changes skill names.

## Writing the agent

- Model and effort: the sizing policy is Sonnet by default, Opus for substantial logic, Fable for design or for the area where one miss is most expensive (the commented `[[model_rules]]` in the example config apply it per change). In the agent file keep `model: sonnet` and `effort: high` for a checklist review; for an area where one missed bug loses money or data, pin `model: opus` (or `fable` for the most expensive area), and say why in a YAML comment next to it. Prefer a pinned model to `inherit`: `inherit` follows the session, so a cheap session would downgrade the reviewer that matters most. Never `haiku` for a reviewer: the config's model keys refuse it, and for this project's agents and the plugin's own, `route --check` flags it and `route --models` refuses to dispatch it. Pros of Sonnet: a fraction of the cost per review. Cons: it may miss a subtle bug that spans several files. The plugin's PreToolUse hook (`hooks/haiku-reviewer-guard.py`) enforces the no-Haiku rule for dispatches: it refuses a reviewer agent launched with a Haiku model.
- Keep verbatim: the read-only tools, the sentence that tells the reviewer to read other refs with `git show`, `git diff` or `git archive <ref> | tar -x -C "$(mktemp -d)"` and never check them out (the plugin's `hooks/reviewer-guard.py` refuses a reviewer's git commands that change a real checkout and its gh commands that write to GitHub, so a reviewer without the sentence learns the rule from a refusal), the judge-only paragraph (the caller passes check results; the agent never re-runs them), the output format and the final verdict line (the review-changes skill relies on them), and the "claims about the system" checklist item (without it, Sonnet trusted a false docstring in a blind re-review).
- The checklist is where the value is: file paths, invariants, the bugs that made the agent necessary (linked). A generic checklist adds nothing. Drop any item a tool can check and automate it instead (a convention test, a lint rule), then list it under the tests the caller runs.
- The `description` names the broad areas and points to `.claude/reviewers.toml`. Paths live only in the config; a copy in the description drifts.

## Routing details

- `[[routes]]` for its paths. A path may have several reviewers: add a route rather than taking a path away from its current reviewer, unless it no longer belongs there.
- Once per project, a `[[mirrors]]` entry so a test counts as the code it tests (the example's fits `tests/<folders>/test_<name>` → `src/<folders>/<name>`; adapt it to the project's layout).
- `[[changed_lines]]` when a line in a shared file belongs to it (a dependency bump of a library it owns).

## Checking

`route --check` until it passes; preview with `route --paths <file>... --explain`, which names the rule behind each reviewer. It fails on a wrong expectation, a route that matches no tracked file, a reviewer with no agent file, and (when `allow_default` is set) a tracked path that falls through to the default reviewer without being listed. When adopting routing, list in `allow_default` only the paths a general review is enough for, each with a comment saying why. Never add a pattern just to quiet `--check` for a path that belongs to a specialist.
