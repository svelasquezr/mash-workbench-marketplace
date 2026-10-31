#!/usr/bin/env python3
"""Print the reviewer agents a change needs, one per line, sorted, from the paths it touches
(with --explain: the rule behind each reviewer).

The routes live in the project, in .claude/reviewers.toml (the add-reviewer skill writes them):
each path gets every reviewer whose route matches it; a test also counts as the code it mirrors;
a path no route claims gets its fallback, else the default reviewer (this plugin's
review-routing:change-reviewer), so no change goes unreviewed. An empty or unreadable change is an error, never "no reviewers".

  reviewers-for-change.py <base>...<head>     a branch since it left base
  reviewers-for-change.py <old>..<new>        between two heads (a fix round)
  reviewers-for-change.py --paths PATH...     preview the routing of some paths
  ... --explain [--format text|markdown]      with any of the three above: which rule gave each
                                              path its reviewers (markdown: a table;
                                              --paths has no diff, so it shows no changed-line rules)
  ... --models                                with any of the three above: "agent<TAB>model" lines,
                                              the model to pass when starting each reviewer ("-":
                                              pass none, the agent file's model: applies)
  ... --title TEXT                            with --models or --explain: a title that
                                              [[model_rules]] title_pattern checks instead of
                                              the range's commit subjects (any one matching)
  reviewers-for-change.py --check             test the config: [[expect]] cases, stale routes,
                                              missing agent files, allow_default coverage,
                                              routed agent files on haiku, stale model rules,
                                              and each [[import_guards]] entry
Standard library only; Python 3.11+ (tomllib).
"""

import sys

# Before any route_* import: those modules need Python 3.10+ (and route_config needs tomllib) and
# would fail with a traceback.
try:
    import tomllib  # noqa: F401
except ModuleNotFoundError:  # Python < 3.11
    print("reviewers-for-change: needs Python 3.11 or newer (tomllib)", file=sys.stderr)
    sys.exit(1)

import argparse
import subprocess
from pathlib import Path

# The modules next to this script ship with it; find them whatever the working directory is.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from route_change import (
    change_in_range,
    range_facts,
)
from route_check import check_config
from route_config import load_config, parse_config
from route_explain import explanation_markdown, explanation_rows, explanation_text
from route_guards import guard_chains
from route_models import reviewer_model
from route_rules import changed_line_matches, reviewers_for_path
from route_types import (
    CONFIG_PATH,
    DEFAULT_REVIEWER,
    EXIT_CODES,
    PROGRAM,
    ChangedLineHit,
    ChangeFacts,
    fail,
)

__all__ = ["changed_line_matches", "main"]  # changed_line_matches: tests load it from this script


def repository_root() -> Path:
    completed = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        fail(f"not inside a git repository: {completed.stderr.strip()}")
    return Path(completed.stdout.strip())


def main() -> None:
    parser = argparse.ArgumentParser(
        prog=PROGRAM,
        description=(
            f"Print the reviewer agents a change needs, one per line, sorted (--explain: the rule"
            f" behind each), from the routes in"
            f" {CONFIG_PATH}. A path no route claims gets its fallback, else {DEFAULT_REVIEWER};"
            " tests count as the code they mirror."
        ),
        epilog=EXIT_CODES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "commit_range",
        nargs="?",
        help="<base>...<head> for a branch since it left base; <old>..<new> between two heads",
    )
    parser.add_argument("--paths", nargs="+", metavar="PATH", help="route these paths (a preview)")
    parser.add_argument(
        "--check",
        action="store_true",
        help="test the routing config: expectations, stale routes, coverage, models, import guards",
    )
    parser.add_argument(
        "--config", type=Path, metavar="FILE", help=f"default: <repository>/{CONFIG_PATH}"
    )
    parser.add_argument(
        "--explain",
        action="store_true",
        help="with a range or --paths: show which rule gave each path its reviewers, each"
        " reviewer's model, and the import guards a changed path is on",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown"),
        default=None,
        help="with --explain: text (default) or a markdown table",
    )
    parser.add_argument(
        "--models",
        action="store_true",
        help="print 'agent<TAB>model' lines: the model to start each reviewer on; '-' means the"
        " agent file's own model: applies",
    )
    parser.add_argument(
        "--title",
        metavar="TEXT",
        help="a title for [[model_rules]] title_pattern, instead of the range's commit subjects (a --paths preview has none)",
    )
    options = parser.parse_args()
    modes = [
        options.commit_range is not None,
        options.paths is not None,
        options.check,
    ]
    if sum(modes) != 1:
        parser.error(
            "give exactly one of: a range (<base>...<head> or <old>..<new>), --paths, --check"
        )
    if options.commit_range is not None and ".." not in options.commit_range:
        parser.error(
            f"{options.commit_range!r} is not a range; use <base>...<head> or <old>..<new>"
        )
    if options.explain and options.check:
        parser.error("--explain shows the routing of a change; it does not combine with --check")
    if options.format is not None and not options.explain:
        parser.error("--format applies only with --explain")
    if options.models and (options.check or options.explain):
        parser.error("--models prints the reviewers with their models; --explain shows them too")
    if options.title is not None and not (options.models or options.explain):
        parser.error("--title is for [[model_rules]]: use it with --models or --explain")

    if options.check:
        root = repository_root()
        config = load_config(options.config or root / CONFIG_PATH)
        problems = check_config(config, root)
        for problem in problems:
            print(f"{PROGRAM}: {problem}", file=sys.stderr)
        if problems:
            sys.exit(1)
        print(
            f"ok: {len(config.expectations)} expectations hold; every route matches a tracked file"
        )
        for guard in config.import_guards:
            print(
                f"ok: import guard '{guard.name}': every file its entry modules import is reviewed"
                f" by {guard.reviewer} or allowed with a reason"
            )
        if config.allow_default is None:
            print(
                "coverage not checked: add allow_default to list the paths that may get only"
                " the default reviewer"
            )
        return

    root = repository_root()
    config_path = options.config or root / CONFIG_PATH
    if options.config is None and not config_path.exists():
        # No routing yet is a normal state (review-changes then sends everything to the default
        # reviewer), so it is a note, not an error; --check and an explicit --config stay strict.
        print(
            f"{PROGRAM}: no {CONFIG_PATH} in {root}, so every path gets {DEFAULT_REVIEWER};"
            " the add-reviewer skill sets up routing (if the project's main branch has one,"
            " update this checkout first: its specialists are missing here)",
            file=sys.stderr,
        )
        config = parse_config({})
    else:
        config = load_config(config_path)
    hits: list[ChangedLineHit] = []
    if options.paths is not None:
        source, changed_paths = "the given paths", options.paths
    else:
        source = f"range {options.commit_range}"
        changed_paths, hits = change_in_range(options.commit_range, config)
    if not changed_paths:
        fail(f"no changed files in {source}; check the range")
    extra_reviewers = {
        reviewer for hit in hits for reviewer in config.changed_lines[hit.rule_index].reviewers
    }
    reviewers = sorted(
        extra_reviewers.union(*(reviewers_for_path(path, config) for path in changed_paths))
    )
    if not options.explain and not options.models:
        print("\n".join(reviewers))
        return

    # The facts model rules look at, read only when a rule needs them.
    facts = ChangeFacts((options.title,) if options.title else (), None)
    if config.model_rules and options.commit_range is not None:
        range_facts_found = range_facts(options.commit_range)
        facts = ChangeFacts(facts.titles or range_facts_found.titles, range_facts_found.added_lines)
    resolved = [
        (reviewer, *reviewer_model(reviewer, changed_paths, facts, config, root))
        for reviewer in reviewers
    ]
    if options.models:
        print(
            "\n".join(
                f"{reviewer}\t{model if passed else '-'}" for reviewer, model, _, passed in resolved
            )
        )
        return
    models = [(reviewer, model, why) for reviewer, model, why, _ in resolved]
    rows = explanation_rows(changed_paths, hits, config)
    guards = guard_chains(changed_paths, config, root)
    if options.format == "markdown":
        print(explanation_markdown(rows, models, guards, reviewers))
    else:
        print(explanation_text(rows, models, guards, reviewers))


if __name__ == "__main__":
    main()
