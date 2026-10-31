"""--explain: the rule behind each reviewer, as text or a Markdown table."""

import re

from route_rules import explain_path
from route_types import ChangedLineHit, Config, Why, one_line


def explanation_rows(
    changed_paths: list[str], hits: list[ChangedLineHit], config: Config
) -> list[tuple[str, str, Why]]:
    """(path, reviewer, why) rows in the order the paths changed, each path once."""
    rows: list[tuple[str, str, Why]] = []
    for path in dict.fromkeys(changed_paths):
        rows += [(path, reviewer, why) for reviewer, why in explain_path(path, config)]
        for hit in hits:
            if hit.path == path:
                rule = config.changed_lines[hit.rule_index]
                why = Why(f"changed line in {path} matching", rule.line_pattern.pattern, rule.reason)
                rows += [(path, reviewer, why) for reviewer in rule.reviewers]
    return rows


def explanation_text(
    rows: list[tuple[str, str, Why]],
    models: list[tuple[str, str, Why]],
    guards: list[tuple[str, str, tuple[str, ...]]],
    reviewers: list[str],
) -> str:
    width = max(len(reviewer) for _, reviewer, _ in rows) + 2
    lines: list[str] = []
    previous_path = None
    for path, reviewer, why in rows:
        if path != previous_path:
            lines.append(one_line(path))
            previous_path = path
        lines.append(f"  {reviewer:<{width}}{why.text()}")
    if guards:
        lines.append("import guards:")
        lines += [
            f"  {one_line(path)}: on import guard '{name}' via {' → '.join(chain)}"
            for path, name, chain in guards
        ]
    lines.append("models:")
    lines += [f"  {reviewer}: {model} ({why.text()})" for reviewer, model, why in models]
    lines.append(f"reviewers: {', '.join(reviewers)}")
    return "\n".join(lines)


def markdown_text(text: str) -> str:
    """Free text for a table cell: one line, Markdown and HTML characters escaped, and no
    @mention (a zero-width space after @ keeps a reason from pinging someone)."""
    text = one_line(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"([\\`*_\[\]|~])", r"\\\1", text)
    return text.replace("@", "@\u200b")


def markdown_code(text: str) -> str:
    """A code span for a table cell that holds any text: a fence longer than any run of
    backticks inside, padded when the text starts or ends with one; | escaped for the table."""
    text = one_line(text).replace("|", "\\|")
    fence = "`" * (max((len(run) for run in re.findall("`+", text)), default=0) + 1)
    padding = " " if text.startswith("`") or text.endswith("`") else ""
    return f"{fence}{padding}{text}{padding}{fence}"


def markdown_why(why: Why) -> str:
    cell = markdown_text(why.label)
    if why.pattern is not None:
        cell += f" {markdown_code(why.pattern)}"
    if why.reason:
        cell += f" — {markdown_text(why.reason)}"
    return cell + markdown_text(why.suffix)


def explanation_markdown(
    rows: list[tuple[str, str, Why]],
    models: list[tuple[str, str, Why]],
    guards: list[tuple[str, str, tuple[str, ...]]],
    reviewers: list[str],
) -> str:
    lines = ["### Review routing", "", "| Path | Reviewer | Why |", "|---|---|---|"]
    lines += [
        f"| {markdown_code(path)} | {markdown_text(reviewer)} | {markdown_why(why)} |"
        for path, reviewer, why in rows
    ]
    if guards:
        lines += ["", "| Path | Import guard | Imported via |", "|---|---|---|"]
        lines += [
            f"| {markdown_code(path)} | {markdown_text(name)} | {markdown_code(' → '.join(chain))} |"
            for path, name, chain in guards
        ]
    lines += ["", "| Reviewer | Model | Why |", "|---|---|---|"]
    lines += [
        f"| {markdown_text(reviewer)} | {markdown_text(model)} | {markdown_why(why)} |"
        for reviewer, model, why in models
    ]
    lines += ["", f"**Reviewers:** {markdown_text(', '.join(reviewers))}"]
    return "\n".join(lines)
