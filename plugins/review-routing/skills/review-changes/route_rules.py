"""Which reviewers a path needs, and why (routes, mirrors, fallbacks)."""

import re

from route_types import Config, Mirror, Why


def mirrored_source_paths(path: str, mirrors: tuple[Mirror, ...]) -> list[str]:
    """The code a test may stand for, from the first mirror that matches. With shorter_names,
    tests/cli/test_data_inspect.py also stands for cli/data.py (`_<part>`s dropped from the end
    of the name); extra candidates only add reviewers."""
    for mirror in mirrors:
        match = mirror.pattern.search(path)
        if not match:
            continue
        source = match.expand(mirror.source)
        candidates = [source]
        if mirror.shorter_names:
            folder, slash, name = source.rpartition("/")
            stem, dot, extension = name.partition(".")
            pieces = stem.split("_")
            candidates += [
                f"{folder}{slash}{'_'.join(pieces[:count])}{dot}{extension}"
                for count in range(len(pieces) - 1, 0, -1)
            ]
        return candidates
    return []


def routed_reviewers(path: str, config: Config) -> set[str]:
    """Reviewers from routes alone: the path's own, and those of the code it mirrors."""
    candidates = [path, *mirrored_source_paths(path, config.mirrors)]
    return {
        reviewer
        for candidate in candidates
        for route in config.routes
        if route.pattern.search(candidate)
        for reviewer in route.reviewers
    }


def explain_path(path: str, config: Config) -> list[tuple[str, Why]]:
    """(reviewer, why) for each reviewer the path's routes, its fallback or the default give it."""
    explained: dict[str, Why] = {}  # reviewer -> the first rule that gave it
    candidates = [
        (path, ""),
        *(
            (source, f"mirror of {source}: ")
            for source in mirrored_source_paths(path, config.mirrors)
        ),
    ]
    for candidate, prefix in candidates:
        for number, route in enumerate(config.routes, start=1):
            if route.pattern.search(candidate):
                why = Why(f"{prefix}route #{number}", route.pattern.pattern, route.reason)
                for reviewer in route.reviewers:
                    explained.setdefault(reviewer, why)
    if explained:
        return list(explained.items())
    for fallback in config.fallbacks:
        if fallback.pattern.search(path):
            why = Why("fallback", fallback.pattern.pattern, fallback.reason)
            return [(reviewer, why) for reviewer in fallback.reviewers]
    allowed = next(
        (entry for entry in config.allow_default or () if entry.pattern.search(path)), None
    )
    if allowed is None:
        return [(config.default_reviewer, Why("default"))]
    why = Why("default (allow_default", allowed.pattern.pattern, allowed.reason, ")")
    return [(config.default_reviewer, why)]


def repr_pattern(pattern: re.Pattern[str]) -> str:
    return f"'{pattern.pattern}'"


def reviewers_for_path(path: str, config: Config) -> set[str]:
    return {reviewer for reviewer, _ in explain_path(path, config)}


def changed_line_matches(patch: str, line_pattern: re.Pattern[str]) -> bool:
    """A changed line (not context, not the +++/--- file headers) matches. The pattern sees the
    line without its +/- prefix, so `^` anchors at the content. The headers are only the lines
    before a file's first hunk (`@@`); after it, `--- x` is a removed `-- x` line."""
    in_header = True
    for line in patch.split("\n"):
        line = line.removesuffix("\r")
        if line.startswith("diff --git "):
            in_header = True
        elif line.startswith("@@"):
            in_header = False
        elif not in_header and line[:1] in ("+", "-") and line_pattern.search(line[1:]):
            return True
    return False
