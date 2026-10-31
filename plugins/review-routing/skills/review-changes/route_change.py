"""Read a change (a range): its paths, changed-line hits and facts."""

import subprocess

from route_rules import changed_line_matches
from route_types import ChangedLineHit, ChangeFacts, Config, fail


def text_of(output: bytes) -> str:
    # Bytes decoded here, not text=True: universal newlines would turn a lone \r inside a changed
    # line into a line end, and only "\n" may end one.
    return output.decode("utf-8", errors="replace")


def run_git(*arguments: str) -> str:
    completed = subprocess.run(["git", *arguments], capture_output=True, check=False)
    if completed.returncode != 0:
        fail(f"git {' '.join(arguments[:2])} failed: {text_of(completed.stderr).strip()}")
    return text_of(completed.stdout)


def run_git_diff(commit_range: str, *options: str, paths: tuple[str, ...] = ()) -> str:
    # Plain output whatever the user's git config: no colours, external diff tools or text
    # conversion, paths from the repository root; --no-renames lists a rename's old and new path.
    # --literal-pathspecs: a changed path such as app/[id].tsx is a file name, not a glob.
    completed = subprocess.run(
        [
            "git",
            "--literal-pathspecs",
            "diff",
            "--no-renames",
            "--no-relative",
            "--no-color",
            "--no-ext-diff",
            "--no-textconv",
            *options,
            commit_range,
            "--",
            *paths,
        ],
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        fail(f"git could not read the range {commit_range}: {text_of(completed.stderr).strip()}")
    return text_of(completed.stdout)


def change_in_range(commit_range: str, config: Config) -> tuple[list[str], list[ChangedLineHit]]:
    """The changed paths, and where a changed line matched a [[changed_lines]] rule."""
    changed_paths = [
        path for path in run_git_diff(commit_range, "--name-only", "-z").split("\0") if path
    ]
    diffs: dict[tuple[str, ...], str] = {}

    def diff_of(paths: tuple[str, ...]) -> str:
        if paths not in diffs:
            diffs[paths] = run_git_diff(commit_range, paths=paths)
        return diffs[paths]

    hits: list[ChangedLineHit] = []
    for rule_index, rule in enumerate(config.changed_lines):
        matching_paths = tuple(path for path in changed_paths if rule.path_pattern.search(path))
        # One diff decides whether the rule applies; only then, one per file to say where.
        if not matching_paths or not changed_line_matches(
            diff_of(matching_paths), rule.line_pattern
        ):
            continue
        if len(matching_paths) == 1:
            hits.append(ChangedLineHit(rule_index, matching_paths[0]))
            continue
        hits += [
            ChangedLineHit(rule_index, path)
            for path in matching_paths
            if changed_line_matches(diff_of((path,)), rule.line_pattern)
        ]
    return changed_paths, hits


def range_facts(commit_range: str) -> ChangeFacts:
    """A range's commit subjects (only the head's side of <base>...<head>) and added lines. With
    --no-renames a moved file counts all its lines as added."""
    log_options = ["--right-only"] if "..." in commit_range else []
    # Split on "\n" only: splitlines() would also end a subject at a lone \r, \x0b, U+2028 and so on.
    subjects = run_git("log", "--format=%s", *log_options, commit_range).split("\n")[:-1]
    added_lines = []
    # numstat -z: "<added>\t<deleted>\t<path>\0"; a binary file shows "-" (no lines).
    for record in run_git_diff(commit_range, "--numstat", "-z").split("\0"):
        added, _, rest = record.partition("\t")
        _, _, file_path = rest.partition("\t")
        if file_path:
            added_lines.append(((file_path,), int(added) if added.isdigit() else 0))
    return ChangeFacts(tuple(subjects), tuple(added_lines))
