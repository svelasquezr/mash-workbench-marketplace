#!/usr/bin/env python3
"""Print corrections and Bash command sequences that recur across a project's past Claude Code sessions.

/forge sees only the current session and the backlog; this script gives it the earlier sessions. It reads
the project's transcripts (<projects-dir>/<slug>/*.jsonl, plus the project's worktrees' <slug>--claude-worktrees-*
folders), keeps sessions active in the last --days days, and prints, at most --limit lines of each kind:

  correction · <n> sessions (<dates>) · "<the wording the sessions' corrections share; other words show as …>"
  sequence · <n> sessions (<dates>) · <cmd> → <cmd> → <cmd>

Only wording that recurs is printed: in a correction's example, every word that no other session's prompt of the
group contains is replaced by "…", so something typed once (a name, a path, a secret) does not reach the output.
Transcript files that are symbolic links leading out of the projects folder are not read. The projects folder is
$CLAUDE_CONFIG_DIR/projects when that is set, else ~/.claude/projects.
A correction is a user prompt that matches a fixed list of correction phrases ("No, ...", "I said", "stop doing",
"don't use", "you keep", "... again" next to "wrong" or "forgot"); two corrections are
the same when they share at least 2 words of 3+ letters, half of the shorter one's. A sequence is 3 Bash calls in a
row, each cut to its program plus subcommand or script name ("git -C dir fetch origin" → "git fetch",
"bash /path/x.sh -v" → "bash x.sh", "bash -lc ..." → "bash"), looking through timeout, sudo and env; browsing
commands (cd, ls, cat, grep, ...) are left out. Commands are split on operators outside quotes, and only
name-like tokens are printed, so quoted text, option values, paths and inline code are not. Prompts from peer
agents, the SDK, hooks (isMeta), injected notices, local command output and anything over 500 characters are not
counted as typed corrections. A message a resumed or forked session copied into its own file counts once. Only
patterns seen in 2 or more sessions are printed. Subagent prompts and tool results are not the user's words.
Read-only: it never writes the backlog or the transcripts, and prints no whole transcript.
Limits: worktrees outside <project>/.claude/worktrees/ and projects whose folder name Claude Code shortened are
not found.
Pros: no model call, cheap enough for every /forge. Cons: a phrase list and word overlap miss paraphrases
and group loosely; /forge judges each line. Standard library only.
"""

import argparse
import datetime
import json
import os
import re
import shlex
from collections import defaultdict
from pathlib import Path

CORRECTION_PATTERNS = [
    r"^\s*no[,.!]",
    r"\bi (?:already )?(?:said|told you|asked(?: you)?)\b",
    r"\bas i (?:said|mentioned)\b",
    r"\b(?:stop|quit) (?:doing|using|adding|making|writing|running)\b",
    r"\b(?:don['’]?t|do not|never) (?:do|use|add|make|run|put|write|create|call|change|touch|commit|push)\b",
    r"\bthat['’]?s (?:wrong|not (?:right|what))\b",
    r"\byou keep\b",
    r"\byou (?:did|made|added|used)\b.{0,40}\bagain\b",
    r"\bsame (?:mistake|error|problem)\b",
    r"\b(?:wrong|forgot|forgotten|missing|left|broke)\b.{0,60}\bagain\b",
    r"\bagain\b.{0,60}\b(?:wrong|forgot|forgotten|missing|left|broke)\b",
]
CORRECTION = re.compile("|".join(CORRECTION_PATTERNS), re.IGNORECASE)
BROWSING = set(
    "cd ls cat head tail echo pwd grep rg find sed wc sleep true printf less tree which".split()
)
SUBCOMMAND_TOOLS = set(
    "git gh npm npx pnpm yarn uv uvx docker pre-commit cargo claude make pip kubectl".split()
)
INTERPRETERS = set("bash sh zsh python python3 node".split())
NOT_TYPED = (
    "<agent-message",
    "<task-notification",
    "<system-reminder",
    "<command-",
    "<local-command-",
    "<bash-",
)
WRAPPERS = {
    "timeout": 1,
    "sudo": 0,
    "env": 0,
    "nice": 0,
    "time": 0,
}  # program: positional arguments to skip
WRAPPER_VALUE_OPTIONS = {
    "-s",
    "--signal",
    "-k",
    "--kill-after",
    "-u",
    "-g",
    "--user",
    "--group",
    "--unset",
    "-n",
}
INLINE_CODE_FLAGS = set(
    "cep"
)  # a short option cluster holding one of these (-c, -lc, -pe, -Sc) runs inline code
VALUE_OPTIONS = {
    "-C",
    "-R",
    "-n",
    "-c",
    "--repo",
    "--namespace",
    "--context",
    "--directory",
    "--git-dir",
    "--work-tree",
    "--kubeconfig",
    "--project",
    "--config",
    "-f",
    "--file",
    "--filter",
}  # skip their value
INLINE_CODE_OPTIONS = {"--eval", "--print", "--command"}
SHELL_KEYWORDS = set("if then else elif fi for while until do done case esac ! { }".split())
LOOP_HEADERS = {"for", "select", "case"}
SEPARATORS = {"&&", "||", ";", "|", "&", "(", ")", "|&", ";;"}
NAME = re.compile(
    r"[A-Za-z0-9._+-]+"
)  # all a printed token may hold: no quotes, spaces, slashes or "="
SUBCOMMAND = re.compile(r"[a-z][a-z0-9-]*")
SCRIPT = re.compile(r"[A-Za-z0-9._+-]+\.[A-Za-z0-9]+")
MAX_PROMPT_CHARS = 500
STOPWORDS = set(
    "the and for you not that this with are was but have from your all can its use don".split()
)


def default_projects_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "projects"


def inside(path: Path, folder: Path) -> bool:
    """True when path, symlinks resolved, lies under folder: a link out of the projects folder is not read."""
    try:
        path.resolve().relative_to(folder.resolve())
    except (OSError, ValueError):
        return False
    return True


def masked_example(prompts: list[str]) -> str:
    """The first prompt with each word that no other prompt of its group contains replaced by "…".

    Only wording that recurs across sessions is shown, so what was typed once (a name, a path, a secret) is not
    printed; a long run of characters is hidden even when it recurs.
    """

    def norm(token: str) -> str:
        return re.sub(r"[^a-z0-9']+", "", token.lower())

    shared = {norm(t) for prompt in prompts[1:] for t in prompt.split()} - {""}
    pieces: list[str] = []
    for token in prompts[0].split():
        piece = token if norm(token) in shared and len(token) < 20 else "…"
        if piece != "…" or not pieces or pieces[-1] != "…":
            pieces.append(piece)
    return " ".join(pieces)


def project_folders(projects_dir: Path, project: str) -> list[Path]:
    slug = re.sub(r"[^A-Za-z0-9-]", "-", str(Path(project).resolve()))
    if not projects_dir.is_dir():
        return []
    return [
        p
        for p in projects_dir.iterdir()
        if p.is_dir()
        and inside(p, projects_dir)
        and (p.name == slug or p.name.startswith(slug + "--claude-worktrees-"))
    ]


def read_session(path: Path, seen: set[str]) -> tuple[list[datetime.date], list[str], list[str]]:
    """Dates, user prompts and Bash commands of one transcript, in order. A resumed or forked session copies the
    earlier conversation, with the same message uuids, into a new file: an entry whose uuid is in `seen` was
    already counted and is skipped."""
    dates, prompts, commands = [], [], []
    with open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(entry, dict) or entry.get("isSidechain"):
                continue
            uuid = entry.get("uuid")
            if isinstance(uuid, str):
                if uuid in seen:
                    continue
                seen.add(uuid)
            stamp = entry.get("timestamp")
            if isinstance(stamp, str):
                try:
                    dates.append(datetime.date.fromisoformat(stamp[:10]))
                except ValueError:
                    pass
            content = (
                (entry.get("message") or {}).get("content")
                if isinstance(entry.get("message"), dict)
                else None
            )
            if (
                entry.get("type") == "user"
                and isinstance(content, str)
                and typed_by_user(entry, content)
            ):
                prompts.append(content)
            elif entry.get("type") == "assistant" and isinstance(content, list):
                for block in content:
                    if (
                        isinstance(block, dict)
                        and block.get("type") == "tool_use"
                        and block.get("name") == "Bash"
                    ):
                        command = (block.get("input") or {}).get("command")
                        shortened = (
                            short_command(command)
                            if isinstance(command, str) and command.strip()
                            else ""
                        )
                        if shortened:
                            commands.append(shortened)
    return dates, prompts, commands


def typed_by_user(entry: dict, content: str) -> bool:
    """A prompt the person typed: not a peer agent's message, an SDK or system prompt, or an injected notice."""
    if entry.get("isMeta"):
        return False
    origin = entry.get("origin")
    if isinstance(origin, dict) and origin.get("kind") not in (None, "human"):
        return False
    if entry.get("promptSource") in ("sdk", "system") or entry.get("entrypoint") == "sdk-cli":
        return False
    return len(content) <= MAX_PROMPT_CHARS and not any(marker in content for marker in NOT_TYPED)


def segments(command: str) -> list[list[str]]:
    """The command's first line as simple commands (lists of words), split on shell operators outside quotes,
    with redirections and their targets removed; words after a quote left open on that line are dropped."""
    lexer = shlex.shlex(
        command.strip().splitlines()[0] if command.strip() else "",
        posix=True,
        punctuation_chars=True,
    )
    lexer.whitespace_split = True
    tokens = []
    try:
        tokens.extend(lexer)  # keeps the tokens read before an error
    except ValueError:
        pass  # an open quote or a trailing backslash (a heredoc or a continued line): keep what came before it
    result, current, skip_next = [], [], False
    for token in tokens:
        if skip_next:
            skip_next = False
        elif token in SEPARATORS:
            result.append(current)
            current = []
        elif set(token) <= set("<>&"):
            skip_next = True
            if current and current[-1].isdigit():
                current.pop()  # the 2 of 2>&1
        else:
            current.append(token)
    return [*result, current]


def short_command(command: str) -> str:
    """The program, plus its subcommand (git, gh, ...) or script file name (bash, python3, ...), from the first
    simple command that is not a browsing command; "" when there is none. Only name-like tokens are printed, so
    quoted text, inline code (-c, -lc, -e, -pe, -p), option values, paths and prompts stay out."""
    for words in segments(command):
        if words and words[0] in LOOP_HEADERS:
            continue  # "for x in ...": no command until "do", which starts a later segment
        while words and (
            words[0] in SHELL_KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])
        ):
            words = words[1:]  # if/for/while/..., and VAR=value prefixes
        while words and Path(words[0]).name in WRAPPERS:
            skip = WRAPPERS[Path(words[0]).name]
            words = words[1:]
            while words and (words[0].startswith("-") or "=" in words[0]):
                words = words[2:] if words[0] in WRAPPER_VALUE_OPTIONS else words[1:]
            words = words[skip:]
        if not words:
            continue
        program = Path(words[0]).name
        if not NAME.fullmatch(program) or program in BROWSING:
            continue
        if program not in SUBCOMMAND_TOOLS | INTERPRETERS:
            return program
        rest = words[1:]
        while rest:
            token = rest.pop(0)
            if program in INTERPRETERS | {"claude"} and token in INLINE_CODE_OPTIONS:
                return program
            if program in INTERPRETERS | {"claude"} and re.fullmatch(r"-[A-Za-z]+", token):
                if INLINE_CODE_FLAGS & set(token[1:]):
                    return program
            elif token in VALUE_OPTIONS:
                rest = rest[1:]
            elif not token.startswith("-"):
                if program in INTERPRETERS:
                    name = Path(token).name
                    return f"{program} {name}" if SCRIPT.fullmatch(name) else program
                return f"{program} {token}" if SUBCOMMAND.fullmatch(token) else program
        return program
    return ""


def words(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-z]+", text.lower()) if len(w) >= 3 and w not in STOPWORDS}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--project", default=str(Path.cwd()), help="the project's path (default: current directory)"
    )
    parser.add_argument("--projects-dir", default=str(default_projects_dir()))
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument(
        "--today",
        type=datetime.date.fromisoformat,
        default=datetime.datetime.now(datetime.UTC).date(),
    )
    args = parser.parse_args()

    transcripts = [
        t
        for folder in project_folders(Path(args.projects_dir), args.project)
        for t in folder.glob("*.jsonl")
        if inside(t, Path(args.projects_dir))
    ]
    if not transcripts:
        print(f"no transcripts for {args.project} under {args.projects_dir}")
        return
    since = args.today - datetime.timedelta(days=args.days)
    seen: set[str] = set()
    groups: list[
        tuple[set[str], dict[str, str], set[datetime.date], set[str]]
    ] = []  # words, one prompt per session, dates, sessions
    sequences: dict[str, dict[str, datetime.date]] = defaultdict(dict)
    for transcript in transcripts:
        dates, prompts, commands = read_session(transcript, seen)
        if not dates or max(dates) < since:
            continue
        session, day = str(transcript), min(dates)
        for prompt in prompts:
            if not CORRECTION.search(prompt):
                continue
            prompt_words = words(prompt)
            for group_words, examples, group_dates, sessions in groups:
                shared = len(prompt_words & group_words)
                if shared >= 2 and shared * 2 >= min(len(prompt_words), len(group_words)):
                    group_dates.add(day)
                    sessions.add(session)
                    examples.setdefault(session, prompt)
                    break
            else:
                groups.append((prompt_words, {session: prompt}, {day}, {session}))
        collapsed = [c for i, c in enumerate(commands) if i == 0 or c != commands[i - 1]]
        for i in range(len(collapsed) - 2):
            sequences[" → ".join(collapsed[i : i + 3])].setdefault(session, day)

    def dates_text(dates) -> str:
        return ", ".join(str(d) for d in sorted(set(dates)))

    repeated = sorted((g for g in groups if len(g[3]) >= 2), key=lambda g: -len(g[3]))[: args.limit]
    for _, examples, dates, sessions in repeated:
        shortened = masked_example(list(examples.values()))
        shortened = shortened[:100] + ("…" if len(shortened) > 100 else "")
        print(f'correction · {len(sessions)} sessions ({dates_text(dates)}) · "{shortened}"')
    common = sorted((s for s in sequences.items() if len(s[1]) >= 2), key=lambda s: -len(s[1]))[
        : args.limit
    ]
    for sequence, sessions in common:
        print(f"sequence · {len(sessions)} sessions ({dates_text(sessions.values())}) · {sequence}")


if __name__ == "__main__":
    main()
