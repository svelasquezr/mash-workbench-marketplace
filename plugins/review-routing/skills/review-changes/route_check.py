"""--check: test the routing config against the repository."""

from pathlib import Path

from route_change import run_git
from route_guards import guard_problems
from route_models import agent_file, frontmatter, frontmatter_model
from route_rules import repr_pattern, reviewers_for_path, routed_reviewers
from route_types import BUILT_IN_AGENTS, Config


def agent_names(repository_root: Path) -> set[str]:
    """Names of the project's agents: each .claude/agents/*.md file's stem and its `name:`."""
    names = set()
    for definition in (repository_root / ".claude" / "agents").glob("*.md"):
        names.add(definition.stem)
        name = frontmatter(definition).get("name")
        if name:
            names.add(name)
    return names


def check_config(config: Config, repository_root: Path) -> list[str]:
    problems = []
    for expectation in config.expectations:
        actual = reviewers_for_path(expectation.path, config)
        if actual != expectation.reviewers:
            problems.append(
                f"expect: {expectation.path}: expected {', '.join(sorted(expectation.reviewers))};"
                f" got {', '.join(sorted(actual))}"
            )

    tracked_paths = [
        path for path in run_git("-C", str(repository_root), "ls-files", "-z").split("\0") if path
    ]
    pattern_owners = [
        *(("routes", route.pattern) for route in config.routes),
        *(("fallbacks", fallback.pattern) for fallback in config.fallbacks),
        *(("changed_lines", rule.path_pattern) for rule in config.changed_lines),
    ]
    for key, pattern in pattern_owners:
        if not any(pattern.search(path) for path in tracked_paths):
            problems.append(
                f"{key}: '{pattern.pattern}' matches no tracked file (renamed or removed?)"
            )

    known_agents = agent_names(repository_root) | BUILT_IN_AGENTS
    named_reviewers = {config.default_reviewer}.union(
        *(route.reviewers for route in config.routes),
        *(fallback.reviewers for fallback in config.fallbacks),
        *(rule.reviewers for rule in config.changed_lines),
        (guard.reviewer for guard in config.import_guards),
    )
    for reviewer in sorted(named_reviewers):
        # plugin-name:agent-name agents live in a plugin, not in the project.
        if ":" not in reviewer and reviewer not in known_agents:
            problems.append(f"reviewer '{reviewer}' has no agent file in .claude/agents/")
        definition = agent_file(reviewer, repository_root)
        model = frontmatter_model(definition) if definition is not None else None
        if model is not None and "haiku" in model.lower():
            problems.append(
                f"{reviewer} runs on haiku ({definition}: model: {model}); reviewers run on"
                " sonnet, opus or fable"
            )
        elif model == "":
            problems.append(f"{reviewer}'s agent file has an empty model: ({definition})")

    for number, rule in enumerate(config.model_rules, start=1):
        where = f"model_rules[{number}]"
        if rule.reviewer not in named_reviewers:
            problems.append(
                f"{where}: {rule.reviewer} is not routed (no route, fallback, changed_lines rule"
                " or default names it)"
            )
        if rule.path_pattern is not None and not any(
            rule.path_pattern.search(path) for path in tracked_paths
        ):
            problems.append(
                f"{where}: {repr_pattern(rule.path_pattern)} matches no tracked file"
                " (renamed or removed?)"
            )

    if config.allow_default is not None:
        default_paths = [
            path
            for path in tracked_paths
            if not routed_reviewers(path, config)
            and not any(fallback.pattern.search(path) for fallback in config.fallbacks)
        ]
        unlisted = [
            path
            for path in default_paths
            if not any(allowed.pattern.search(path) for allowed in config.allow_default)
        ]
        problems += [
            f"{path}: only {config.default_reviewer} reviews it;"
            " add a route, or a pattern to allow_default"
            for path in unlisted
        ]
        problems += [
            f"allow_default: {repr_pattern(allowed.pattern)} matches no path that falls back to"
            f" {config.default_reviewer} (stale?)"
            for allowed in config.allow_default
            if not any(allowed.pattern.search(path) for path in default_paths)
        ]
    for guard in config.import_guards:
        problems += guard_problems(guard, config, repository_root)
    return problems
