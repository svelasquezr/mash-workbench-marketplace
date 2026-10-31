"""Read and validate .claude/reviewers.toml into a Config."""

import re
import tomllib  # the entry point has checked that it exists
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from route_types import (
    CONFIG_MODELS,
    DEFAULT_REVIEWER,
    MODULE_NAME,
    TOP_LEVEL_KEYS,
    AllowDefault,
    ChangedLinesRoute,
    Config,
    Expectation,
    GuardAllow,
    ImportGuard,
    Mirror,
    ModelRule,
    Route,
    fail,
)


class ConfigError(Exception):
    pass


def model_name(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ConfigError(f"{where} must be a model name: sonnet, opus or fable")
    if "haiku" in value.lower():
        raise ConfigError(
            f"{where} is {value!r}: reviewers never run on haiku (in a blind review test it"
            " accepted a false premise and answered SAFE TO LAND); use sonnet, opus or fable"
        )
    if value not in CONFIG_MODELS:
        raise ConfigError(
            f"{where} is {value!r}: use sonnet, opus or fable (the models a reviewer can be"
            " started on); leave it out to keep the agent file's model"
        )
    return value


def model_rule(entry: dict[str, Any], where: str) -> ModelRule:
    if not isinstance(entry["reviewer"], str) or not entry["reviewer"].strip():
        raise ConfigError(f"{where}.reviewer must be an agent name")
    path_pattern = (
        compile_pattern(entry["path_pattern"], f"{where}.path_pattern")
        if "path_pattern" in entry
        else None
    )
    min_added_lines = entry.get("min_added_lines")
    if min_added_lines is not None:
        if path_pattern is None:
            raise ConfigError(f"{where}: min_added_lines needs path_pattern (lines added where?)")
        if isinstance(min_added_lines, bool) or not isinstance(min_added_lines, int):
            raise ConfigError(f"{where}.min_added_lines must be a whole number of at least 1")
        if min_added_lines < 1:
            raise ConfigError(f"{where}.min_added_lines must be a whole number of at least 1")
    return ModelRule(
        reviewer=entry["reviewer"],
        model=model_name(entry["model"], f"{where}.model"),
        title_pattern=(
            compile_pattern(entry["title_pattern"], f"{where}.title_pattern")
            if "title_pattern" in entry
            else None
        ),
        path_pattern=path_pattern,
        min_added_lines=min_added_lines,
        reason=optional_reason(entry, where),
    )


def string_list(value: Any, where: str, example: str) -> tuple[str, ...]:
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item.strip() for item in value)
    ):
        raise ConfigError(f"{where} must be a non-empty list of strings, e.g. [{example}]")
    return tuple(value)


def import_guard(entry: dict[str, Any], where: str) -> ImportGuard:
    if entry["language"] != "python":
        raise ConfigError(f'{where}.language must be "python" (the only language guards read)')
    if not isinstance(entry["name"], str) or not entry["name"].strip():
        raise ConfigError(f'{where}.name must be a short name, e.g. "payment path"')
    if not isinstance(entry["reviewer"], str) or not entry["reviewer"].strip():
        raise ConfigError(f"{where}.reviewer must be an agent name")
    allow_values = entry.get("allow", [])
    if not isinstance(allow_values, list) or not all(
        isinstance(item, dict) for item in allow_values
    ):
        raise ConfigError(f"{where}.allow must be a list of {{ path or pattern, reason }} tables")
    allow = []
    for index, item in enumerate(allow_values, start=1):
        allow_where = f"{where}.allow[{index}]"
        check_keys(item, allow_where, {"reason"}, frozenset({"path", "pattern"}))
        if ("path" in item) == ("pattern" in item):
            raise ConfigError(f"{allow_where}: give exactly one of path or pattern")
        reason = optional_reason(item, allow_where)
        assert reason is not None  # required key, checked above
        if "path" in item:
            if not isinstance(item["path"], str) or not item["path"]:
                raise ConfigError(f"{allow_where}.path must be a repository-relative file path")
            allow.append(GuardAllow(item["path"], None, reason))
        else:
            allow.append(
                GuardAllow(None, compile_pattern(item["pattern"], f"{allow_where}.pattern"), reason)
            )
    source_dirs = string_list(entry["source_dirs"], f"{where}.source_dirs", '"src"')
    for source_dir in source_dirs:
        if Path(source_dir).is_absolute() or ".." in Path(source_dir).parts:
            raise ConfigError(
                f"{where}.source_dirs: {source_dir!r} must be a folder inside the repository"
            )
    entry_modules = string_list(entry["entry_modules"], f"{where}.entry_modules", '"app.orders"')
    for entry_module in entry_modules:
        if not MODULE_NAME.fullmatch(entry_module):
            raise ConfigError(
                f"{where}.entry_modules: {entry_module!r} must be a dotted module name, e.g."
                ' "app.orders"'
            )
    return ImportGuard(
        name=entry["name"],
        source_dirs=source_dirs,
        entry_modules=entry_modules,
        reviewer=entry["reviewer"],
        allow=tuple(allow),
    )


def compile_pattern(value: Any, where: str) -> re.Pattern[str]:
    if not isinstance(value, str) or not value:
        raise ConfigError(f"{where} must be a non-empty string (a Python regular expression)")
    try:
        return re.compile(value)
    except re.error as error:
        raise ConfigError(f"{where} is not a valid regular expression: {error}") from error


def reviewer_names(value: Any, where: str) -> tuple[str, ...]:
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(name, str) and name.strip() for name in value)
    ):
        raise ConfigError(
            f'{where} must be a non-empty list of agent names, e.g. ["docs-reviewer"]'
        )
    return tuple(value)


def check_keys(
    entry: dict[str, Any], where: str, required: set[str], optional: frozenset[str]
) -> None:
    missing = sorted(required - entry.keys())
    if missing:
        raise ConfigError(f"{where}: missing key '{missing[0]}'")
    unknown = sorted(entry.keys() - required - optional)
    if unknown:
        expected = ", ".join(sorted(required | optional))
        raise ConfigError(f"{where}: unknown key '{unknown[0]}' (expected {expected})")


def optional_reason(entry: dict[str, Any], where: str) -> str | None:
    reason = entry.get("reason")
    if reason is not None and (not isinstance(reason, str) or not reason.strip()):
        raise ConfigError(f"{where}.reason must be a non-empty string")
    return reason


def tables(
    document: dict[str, Any], key: str, required: set[str], optional: frozenset[str] = frozenset()
) -> Iterator[tuple[str, dict[str, Any]]]:
    """Yield (where, table) for each [[key]] entry, after checking its keys."""
    entries = document.get(key, [])
    if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
        raise ConfigError(f"{key} must be an array of tables: [[{key}]]")
    for index, entry in enumerate(entries, start=1):
        where = f"{key}[{index}]"
        check_keys(entry, where, required, optional)
        yield where, entry


def allow_default_entry(value: Any, where: str) -> AllowDefault:
    """A regular expression, or a { pattern, reason } table."""
    if isinstance(value, dict):
        check_keys(value, where, {"pattern"}, frozenset({"reason"}))
        return AllowDefault(
            compile_pattern(value["pattern"], f"{where}.pattern"), optional_reason(value, where)
        )
    return AllowDefault(compile_pattern(value, where))


def check_template_groups(pattern: re.Pattern[str], source: str, where: str) -> None:
    """A mirror's source may refer only to groups its pattern defines (checked now, not on the
    first matching path)."""
    for reference in re.findall(r"\\g<([^>]*)>|\\(\d+)", source):
        name, number = reference
        if name.isdigit() or number:
            if int(name or number) > pattern.groups:
                raise ConfigError(
                    f"{where}.source refers to group {name or number}, which the pattern lacks"
                )
        elif name not in pattern.groupindex:
            raise ConfigError(f"{where}.source refers to group '{name}', which the pattern lacks")


def parse_config(document: dict[str, Any]) -> Config:
    unknown = sorted(document.keys() - TOP_LEVEL_KEYS)
    if unknown:
        raise ConfigError(
            f"unknown key '{unknown[0]}' (expected {', '.join(sorted(TOP_LEVEL_KEYS))})"
        )
    default_reviewer = document.get("default_reviewer", DEFAULT_REVIEWER)
    if not isinstance(default_reviewer, str) or not default_reviewer.strip():
        raise ConfigError("default_reviewer must be an agent name")
    allow_default = None
    if "allow_default" in document:
        allow_values = document["allow_default"]
        if not isinstance(allow_values, list):
            raise ConfigError(
                "allow_default must be a list of regular expressions or { pattern, reason } tables"
            )
        allow_default = tuple(
            allow_default_entry(value, f"allow_default[{index}]")
            for index, value in enumerate(allow_values, start=1)
        )

    def route_tables(key: str) -> tuple[Route, ...]:
        return tuple(
            Route(
                compile_pattern(entry["pattern"], f"{where}.pattern"),
                reviewer_names(entry["reviewers"], f"{where}.reviewers"),
                optional_reason(entry, where),
            )
            for where, entry in tables(
                document, key, {"pattern", "reviewers"}, frozenset({"reason"})
            )
        )

    mirrors = []
    for where, entry in tables(
        document, "mirrors", {"pattern", "source"}, frozenset({"shorter_names"})
    ):
        pattern = compile_pattern(entry["pattern"], f"{where}.pattern")
        if not isinstance(entry["source"], str) or not entry["source"]:
            raise ConfigError(f"{where}.source must be a non-empty string")
        check_template_groups(pattern, entry["source"], where)
        shorter_names = entry.get("shorter_names", False)
        if not isinstance(shorter_names, bool):
            raise ConfigError(f"{where}.shorter_names must be true or false")
        mirrors.append(Mirror(pattern, entry["source"], shorter_names))

    changed_lines = tuple(
        ChangedLinesRoute(
            compile_pattern(entry["path_pattern"], f"{where}.path_pattern"),
            compile_pattern(entry["line_pattern"], f"{where}.line_pattern"),
            reviewer_names(entry["reviewers"], f"{where}.reviewers"),
            optional_reason(entry, where),
        )
        for where, entry in tables(
            document,
            "changed_lines",
            {"path_pattern", "line_pattern", "reviewers"},
            frozenset({"reason"}),
        )
    )
    expectations = []
    for where, entry in tables(document, "expect", {"path", "reviewers"}):
        if not isinstance(entry["path"], str) or not entry["path"]:
            raise ConfigError(f"{where}.path must be a non-empty string")
        expectations.append(
            Expectation(
                entry["path"], frozenset(reviewer_names(entry["reviewers"], f"{where}.reviewers"))
            )
        )
    default_model = (
        model_name(document["default_model"], "default_model")
        if "default_model" in document
        else None
    )
    model_rules = tuple(
        model_rule(entry, where)
        for where, entry in tables(
            document,
            "model_rules",
            {"reviewer", "model"},
            frozenset({"title_pattern", "path_pattern", "min_added_lines", "reason"}),
        )
    )
    import_guards = tuple(
        import_guard(entry, where)
        for where, entry in tables(
            document,
            "import_guards",
            {"name", "language", "source_dirs", "entry_modules", "reviewer"},
            frozenset({"allow"}),
        )
    )
    return Config(
        default_reviewer=default_reviewer,
        default_model=default_model,
        model_rules=model_rules,
        import_guards=import_guards,
        allow_default=allow_default,
        routes=route_tables("routes"),
        mirrors=tuple(mirrors),
        fallbacks=route_tables("fallbacks"),
        changed_lines=changed_lines,
        expectations=tuple(expectations),
    )


def load_config(config_path: Path) -> Config:
    if not config_path.is_file():
        fail(
            f"no routing config at {config_path}: create it (the review-routing plugin's"
            " add-reviewer skill) or pass --config FILE"
        )
    try:
        document = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as error:
        fail(f"{config_path} is not valid TOML: {error}")
    try:
        return parse_config(document)
    except ConfigError as error:
        fail(f"{config_path}: {error}")
