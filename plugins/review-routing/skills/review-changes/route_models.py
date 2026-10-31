"""The model each reviewer runs on (agent files and [[model_rules]])."""

import re
from pathlib import Path

from route_types import (
    PLUGIN_AGENTS_DIRECTORY,
    PLUGIN_NAME,
    ChangeFacts,
    Config,
    ModelRule,
    Why,
    fail,
)


def frontmatter(agent_file: Path) -> dict[str, str]:
    """The `key: value` lines between an agent file's opening and closing `---`: keys in lower
    case, values without quotes or a trailing comment. Nothing from the body, nothing without a
    closing `---`."""
    lines = agent_file.read_text(encoding="utf-8-sig").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fields: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fields
        match = re.match(r"([A-Za-z_-]+):\s*([^#]*)", line)
        if match:
            fields.setdefault(match.group(1).lower(), match.group(2).strip().strip("'\""))
    return {}


def frontmatter_model(agent_file: Path) -> str | None:
    """The agent file's `model:`; "" when the key is there but empty, None when it is absent."""
    return frontmatter(agent_file).get("model")


def agent_file(reviewer: str, repository_root: Path) -> Path | None:
    """The file that defines a reviewer: this plugin's agents for `review-routing:<name>`, the
    project's .claude/agents/ otherwise (by file name or `name:`); None for other plugins."""
    if ":" in reviewer:
        plugin, _, name = reviewer.partition(":")
        candidate = PLUGIN_AGENTS_DIRECTORY / f"{name}.md"
        return candidate if plugin == PLUGIN_NAME and candidate.is_file() else None
    agents_directory = repository_root / ".claude" / "agents"
    candidate = agents_directory / f"{reviewer}.md"
    if candidate.is_file():
        return candidate
    for other in sorted(agents_directory.glob("*.md")):
        if frontmatter(other).get("name") == reviewer:
            return other
    return None


def rule_holds(rule: ModelRule, changed_paths: list[str], facts: ChangeFacts) -> bool:
    if rule.title_pattern is not None and not any(
        rule.title_pattern.search(title) for title in facts.titles
    ):
        return False
    if rule.path_pattern is None:
        return True
    path_pattern = rule.path_pattern
    if not any(path_pattern.search(path) for path in changed_paths):
        return False
    if rule.min_added_lines is None:
        return True
    if facts.added_lines is None:
        return False  # --paths: no line counts, so the rule can't be shown to hold
    added = sum(
        count
        for paths, count in facts.added_lines
        if any(path_pattern.search(path) for path in paths)
    )
    return added >= rule.min_added_lines


def reviewer_model(
    reviewer: str,
    changed_paths: list[str],
    facts: ChangeFacts,
    config: Config,
    repository_root: Path,
) -> tuple[str, Why, bool]:
    """The model `reviewer` runs on, why, and whether the dispatch must pass it (a model rule or
    default_model) or the agent file's own `model:` applies. A routed agent file on haiku stops
    the dispatch: a reviewer never runs on haiku."""
    definition = agent_file(reviewer, repository_root)
    file_model = frontmatter_model(definition) if definition is not None else None
    if file_model and "haiku" in file_model.lower():
        fail(
            f"{reviewer} runs on haiku ({definition}: model: {file_model}); reviewers run on"
            " sonnet, opus or fable: fix the agent file before dispatching"
        )
    for number, rule in enumerate(config.model_rules, start=1):
        if rule.reviewer == reviewer and rule_holds(rule, changed_paths, facts):
            return rule.model, Why(f"model rule #{number}", reason=rule.reason), True
    if reviewer == config.default_reviewer and config.default_model is not None:
        return config.default_model, Why("default_model"), True
    if not file_model:
        return "-", Why("the agent's own default"), False
    return file_model, Why("agent file"), False
