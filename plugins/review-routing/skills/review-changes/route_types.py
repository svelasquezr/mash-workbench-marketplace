"""Shared constants, the config's and the change's data classes and `fail` for reviewers-for-change."""

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

PROGRAM = "reviewers-for-change"
CONFIG_PATH = ".claude/reviewers.toml"
DEFAULT_REVIEWER = "review-routing:change-reviewer"
BUILT_IN_AGENTS = {"general-purpose"}
# The models a config may name: what the Agent tool's `model` accepts, without haiku. Never haiku for
# a reviewer: in a blind review test a Haiku reviewer accepted a false premise and answered SAFE TO
# LAND.
# Full model IDs are not accepted: probed 2026-10-12, dispatching an agent with
# `model: "claude-opus-5-5"` was rejected by the Agent tool's schema before dispatch ("expected one of
# sonnet|opus|haiku|fable"). So the config keeps the aliases.
CONFIG_MODELS = ("sonnet", "opus", "fable")
MODULE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$")
PLUGIN_AGENTS_DIRECTORY = Path(__file__).resolve().parent.parent.parent / "agents"
PLUGIN_NAME = "review-routing"
TOP_LEVEL_KEYS = {
    "default_reviewer",
    "default_model",
    "model_rules",
    "import_guards",
    "allow_default",
    "routes",
    "mirrors",
    "fallbacks",
    "changed_lines",
    "expect",
}
EXIT_CODES = (
    "exit codes: 0 reviewers printed (or --check passed; with no .claude/reviewers.toml, the"
    " default reviewer and a note on stderr); 1 the change could not be read or is empty, the"
    " config is invalid, missing under --check or --config FILE, or --check found problems"
    " (never means 'no reviewers'); 2 usage"
)


@dataclass(frozen=True)
class Route:
    pattern: re.Pattern[str]
    reviewers: tuple[str, ...]
    reason: str | None = None


@dataclass(frozen=True)
class Mirror:
    pattern: re.Pattern[str]
    source: str
    shorter_names: bool


@dataclass(frozen=True)
class ChangedLinesRoute:
    path_pattern: re.Pattern[str]
    line_pattern: re.Pattern[str]
    reviewers: tuple[str, ...]
    reason: str | None = None


@dataclass(frozen=True)
class AllowDefault:
    pattern: re.Pattern[str]
    reason: str | None = None


@dataclass(frozen=True)
class ChangedLineHit:
    """A changed line matched [[changed_lines]] rule `rule_index` (0-based) in `path`."""

    rule_index: int
    path: str


@dataclass(frozen=True)
class ModelRule:
    """Run `reviewer` on `model` when every condition given holds for the change."""

    reviewer: str
    model: str
    title_pattern: re.Pattern[str] | None = None
    path_pattern: re.Pattern[str] | None = None
    min_added_lines: int | None = None
    reason: str | None = None


@dataclass(frozen=True)
class ChangeFacts:
    """What model rules look at: a range's commit subjects (or
    --title), and the lines each changed file added: (its paths, the count), or None when unknown."""

    titles: tuple[str, ...] = ()
    added_lines: tuple[tuple[tuple[str, ...], int], ...] | None = None


@dataclass(frozen=True)
class GuardAllow:
    """A file an import guard's path may reach without its reviewer: an exact path or a pattern."""

    path: str | None
    pattern: re.Pattern[str] | None
    reason: str

    def matches(self, file_path: str) -> bool:
        if self.path is not None:
            return file_path == self.path
        return self.pattern is not None and bool(self.pattern.search(file_path))

    def describe(self) -> str:
        return (
            self.path
            if self.path is not None
            else f"'{self.pattern.pattern if self.pattern else ''}'"
        )


@dataclass(frozen=True)
class ImportGuard:
    """Every file `entry_modules` import, transitively, is reviewed by `reviewer` or allowed."""

    name: str
    source_dirs: tuple[str, ...]
    entry_modules: tuple[str, ...]
    reviewer: str
    allow: tuple[GuardAllow, ...]


@dataclass(frozen=True)
class Expectation:
    path: str
    reviewers: frozenset[str]


@dataclass(frozen=True)
class Config:
    default_reviewer: str
    default_model: str | None
    model_rules: tuple[ModelRule, ...]
    import_guards: tuple[ImportGuard, ...]
    allow_default: tuple[AllowDefault, ...] | None
    routes: tuple[Route, ...]
    mirrors: tuple[Mirror, ...]
    fallbacks: tuple[Route, ...]
    changed_lines: tuple[ChangedLinesRoute, ...]
    expectations: tuple[Expectation, ...]


def fail(message: str) -> NoReturn:
    print(f"{PROGRAM}: {message}", file=sys.stderr)
    sys.exit(1)


@dataclass(frozen=True)
class Why:
    """Why a path got a reviewer, as `<label> '<pattern>' — <reason><suffix>`. It is kept in parts
    so that each output format quotes the pattern and escapes the free text its own way."""

    label: str
    pattern: str | None = None
    reason: str | None = None
    suffix: str = ""

    def text(self) -> str:
        quoted = f" '{self.pattern}'" if self.pattern is not None else ""
        reason = f" — {self.reason}" if self.reason else ""
        return one_line(f"{self.label}{quoted}{reason}{self.suffix}")


def one_line(text: str) -> str:
    return re.sub(r"\s*[\r\n\v\f\u2028\u2029]+\s*", " ", text)
