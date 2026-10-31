#!/usr/bin/env python3
"""PreToolUse hook for Bash: keep reviewer subagents from changing a real git checkout or writing to GitHub.

Why: reviewers declare Bash (they need `git show`, `git diff`), so "reviewers are read-only"
otherwise rests on one prompt sentence. A reviewer once ran `git checkout origin/<branch>` inside the builder's
worktree and left it on a detached HEAD; others switched the shared checkout to a PR branch, overwrote its index with
`git --work-tree=... checkout FETCH_HEAD -- src`, or left ~25 `pr<N>` branches behind.

Who is guarded: only calls made inside a subagent (the hook input carries `agent_type`; without it the hook exits 0
at once, before any subprocess or file access) whose agent is one of this plugin's reviewers: a `review-routing:`
agent (or a bare name that is one of this plugin's agent files), or an agent the project's routing config names
(`reviewers`, `reviewer` or `default_reviewer` anywhere in the nearest `.claude/reviewers.toml` from the cwd up to
the repository root) and that the project or the user defines in `.claude/agents/`, or that a plugin ships (a
`plugin:name`). Claude Code's built-in agents are never guarded, even when the config names one, because the same
type also builds in that session. Any other agent is left alone, whatever its name or its file says.
haiku-reviewer-guard.py's `is_reviewer` differs on purpose: that hook sees the dispatch prompt, this one sees only
`agent_type`.

Blocks (exit 2, reason on stderr, which Claude Code shows to Claude):
  - git, when it runs in a real repository, unless the subcommand is a read: show diff log blame status grep
    ls-files ls-tree rev-parse rev-list merge-base cat-file describe for-each-ref shortlog archive and a few more,
    `branch`/`tag` only to list, `config` only to read, `remote`/`remote -v`, `stash list|show`,
    `apply --check|--stat`, `fetch` without a `src:dst` refspec, `worktree list`, `reflog` (not expire/delete),
    `remote show`. `git clone` and `git init` are allowed (a clone writes a new directory, a re-init changes nothing),
    except `git init --separate-git-dir`, which moves a repository's git dir.
    A repository is real when `git rev-parse --git-common-dir` resolves outside the temp dirs (tempfile.gettempdir(),
    /tmp and /var/tmp, symlinks resolved), so every worktree of a real repo counts and a `mktemp -d` repo does not. Where git runs follows `cd` earlier in the line
    (a subshell's cd ends at its `)`), `git -C`, `GIT_DIR=`/`GIT_WORK_TREE=` (also `export` and `env`) and
    `--git-dir`/`--work-tree`; a real git dir or a real work tree counts.
  - gh, anywhere, when it writes to GitHub or changes gh's setup: `pr checkout|merge|...|update-branch`,
    `issue create|comment|...`, any group's create, delete, edit, lock, pin, transfer, archive, rename, set, add,
    remove, cancel, rerun, run, upload, install, login, logout (and a few more, GH_ANY_GROUP_WRITES), and `api` with a
    method other than GET (or with -f/-F/--input fields outside graphql and without an explicit GET, which makes gh
    POST). `--help`/`-h` is help, and allowed, for git and gh, unless it comes right after an option, where it
    may be that option's value (`-m -h`, `--body --help`); `git commit -a --help` is refused too, as the guard
    cannot tell a flag from an option that takes a value; after `--` it is a path (`git reset -- a --help`).
    `git --help <command>` only shows the manual and is allowed.

Known gaps (this catches honest mistakes; it is not a security boundary): scripts run from disk, eval, `xargs git`,
paths held in variables or computed by $(...) (an unresolvable target is allowed, which is also what keeps
`cd "$tmp" && git commit` working), GraphQL mutations, gh aliases (`gh alias set` is refused, but an alias set earlier runs),
file writes by `sed -i`, redirects or `tee`, `--output=` options of read subcommands, and review-changes's
`general-purpose` fallback reviewer (a built-in agent), any reviewer the routing config does not name, gh write
actions not listed above, and `git submodule foreach` / `git difftool`, which are refused though they can be reads.
Pros: the commands that already hurt are refused with the read-only way shown. Cons: a creative reviewer gets past.
Anything it cannot parse is allowed: a missed write is acceptable, a blocked unrelated command is a bug.
Standard library only.
"""

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

PUNCTUATION = ";&|()<>\n"
SEPARATOR_CHARACTERS = set(";&|\n()")
KEYWORDS = {
    "if",
    "then",
    "else",
    "elif",
    "fi",
    "do",
    "done",
    "while",
    "until",
    "for",
    "{",
    "}",
    "!",
}
PREFIXES = {"sudo", "env", "command", "time", "nohup", "exec"}
OPTIONS_WITH_VALUE = {
    "sudo": {"-u", "-g", "-p", "-C"},
    "env": {"-u", "-C"},
    "exec": {"-a"},
}
WORD_BREAKS = " \t\r" + PUNCTUATION
SHELLS = {"bash", "sh", "zsh"}
GIT_ENVIRONMENT = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")
GIT_OPTIONS_WITH_VALUE = {
    "-c",
    "--namespace",
    "--exec-path",
    "--super-prefix",
    "--config-env",
    "--attr-source",
}

READ_SUBCOMMANDS = {
    "show", "diff", "log", "blame", "status", "grep", "ls-files", "ls-tree", "rev-parse", "rev-list", "merge-base",
    "cat-file", "describe", "for-each-ref", "shortlog", "archive", "ls-remote", "diff-tree", "diff-index",
    "diff-files", "name-rev", "show-ref", "range-diff", "cherry", "help", "version", "show-branch", "whatchanged",
    "count-objects", "clone", "check-ignore", "check-attr", "check-ref-format", "check-mailmap", "var",
    "verify-commit", "verify-tag", "merge-tree", "patch-id",
}  # fmt: skip
# Options of branch/tag/fetch that take a separate value; the value is not a name or a refspec.
LISTING_VALUE_OPTIONS = {
    "--contains",
    "--no-contains",
    "--merged",
    "--no-merged",
    "--points-at",
    "--sort",
    "--format",
    "--abbrev",
}
BRANCH_FLAGS = set("arvil")  # -a means "annotate" for tag, so the short flags differ
TAG_FLAGS = set("lnv")
FETCH_VALUE_OPTIONS = {
    "--depth", "-j", "--jobs", "--deepen", "--shallow-since", "--shallow-exclude", "--upload-pack", "-o", "--server-option",
    "--negotiation-tip", "--refmap", "--filter", "--submodule-prefix", "--recurse-submodules-default",
}  # fmt: skip
CONFIG_WRITE_FLAGS = {
    "--add", "--unset", "--unset-all", "--replace-all", "--edit", "-e", "--remove-section", "--rename-section", "--set",
}  # fmt: skip
CONFIG_READ_FLAGS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
CONFIG_VALUE_OPTIONS = {"--file", "-f", "--blob"}
GH_PR_WRITES = {
    "checkout",
    "merge",
    "close",
    "reopen",
    "edit",
    "comment",
    "review",
    "ready",
    "create",
    "update-branch",
}
GH_ISSUE_WRITES = {"create", "comment", "close", "edit", "reopen"}
# Actions that change GitHub (or gh's own setup) in any command group: `gh <group> <action>`.
GH_ANY_GROUP_WRITES = {
    "create", "delete", "edit", "close", "reopen", "comment", "lock", "unlock", "pin", "unpin", "transfer",
    "archive", "unarchive", "rename", "set", "remove", "add", "cancel", "rerun", "run", "upload", "develop",
    "install", "upgrade", "logout", "login", "fork", "sync", "enable", "disable", "setup-git", "switch", "import",
    "cp", "link", "unlink", "copy", "mark-template",
}  # fmt: skip
GH_WRITE_PREFIXES = (
    "item-",
    "field-",
    "delete-",
    "set-",
)  # except the reads among them (item-list, field-list)
GH_READ_SUFFIXES = ("-list", "-view")
GH_SUBGROUPS = {
    "deploy-key",
    "autolink",
}  # `gh repo deploy-key add`: the third word is the action
HELP_FLAGS = {"-h", "--help"}


def asks_help(arguments):
    """`-h`/`--help` that git or gh reads as help: not right after an option, where it may be that option's value
    (`-m -h`, `--body --help`)."""
    for index, argument in enumerate(arguments):
        if argument == "--":  # after it, `-h` is a path or a positional, never help
            return False
        if argument in HELP_FLAGS and (index == 0 or not arguments[index - 1].startswith("-")):
            return True
    return False


AGENT_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
GH_FIELD_FLAGS = {"-f", "-F", "--field", "--raw-field", "--input"}
GH_OPTIONS_WITH_VALUE = {"-R", "--repo", "--hostname"}
GH_API_OPTIONS_WITH_VALUE = {
    "-H",
    "--header",
    "-q",
    "--jq",
    "-t",
    "--template",
    "--hostname",
    "--cache",
    "-p",
    "--preview",
}
GIT_REASON = (
    "Reviewers don't change a checkout: read another ref with `git show <ref>:<path>` or `git diff`;"
    ' for its files on disk use `git archive <ref> [paths] | tar -x -C "$(mktemp -d)"`;'
    " do scratch git work in a `mktemp -d` repo."
)
GH_REASON = (
    "Reviewers read GitHub, they don't write to it: use `gh pr diff`, `gh pr view`, `gh api` (GET)."
    " A `gh api` call with -f/-F fields is a POST unless it says `-X GET`."
    " Put findings in your review; the caller posts them."
)


# ---- who is a reviewer ------------------------------------------------------------------------------------------


REVIEWER_KEYS = {"reviewers", "reviewer", "default_reviewer"}


def config_reviewers(cwd: str) -> set[str]:
    """The agent names the nearest .claude/reviewers.toml (from cwd up to the repository root) lists as reviewers.

    Read with tomllib (Python 3.11+). An older Python, no file, or a file that cannot be read gives no names.
    """
    try:
        import tomllib
    except ModuleNotFoundError:
        return set()
    directory = os.path.abspath(cwd)
    while True:
        path = os.path.join(directory, ".claude", "reviewers.toml")
        if os.path.isfile(path):
            try:
                with open(path, "rb") as handle:
                    document = tomllib.load(handle)
            except (OSError, ValueError):
                return set()
            names: set[str] = set()
            pending: list = [document]
            while pending:
                value = pending.pop()
                if isinstance(value, dict):
                    for key, item in value.items():
                        if key in REVIEWER_KEYS:
                            names.update(
                                i
                                for i in (item if isinstance(item, list) else [item])
                                if isinstance(i, str)
                            )
                        else:
                            pending.append(item)
                elif isinstance(value, list):
                    pending.extend(value)
            return names
        parent = os.path.dirname(directory)
        if os.path.exists(os.path.join(directory, ".git")) or parent == directory:
            return set()
        directory = parent


def agent_files(name: str, cwd: str) -> list[str]:
    """Where a project or user agent called name is defined: .claude/agents/ from cwd up to the repository root, and
    ~/.claude/agents/."""
    paths, directory = [], os.path.abspath(cwd)
    while True:
        paths.append(os.path.join(directory, ".claude", "agents", name + ".md"))
        parent = os.path.dirname(directory)
        if os.path.exists(os.path.join(directory, ".git")) or parent == directory:
            break
        directory = parent
    paths.append(os.path.join(os.path.expanduser("~"), ".claude", "agents", name + ".md"))
    return paths


def is_reviewer(agent_type: str, cwd: str) -> bool:
    """review-routing's own agents, and the agents the project's routing config names. Nothing else.

    A bare name from the config counts only when the project or the user defines an agent file for it: Claude Code's
    built-in agents (general-purpose, Explore, Plan, ...) also build and commit in the same session, so a config that
    names one as its reviewer does not make every such agent read-only. A bare name that is one of this plugin's own
    agent files counts too, in case agent_type arrives without the plugin prefix.
    """
    prefix, _, name = agent_type.rpartition(":")
    if prefix == "review-routing":
        return True
    if not AGENT_NAME.fullmatch(name):
        return False
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if (
        not prefix
        and plugin_root
        and os.path.isfile(os.path.join(plugin_root, "agents", name + ".md"))
    ):
        return True
    if agent_type not in config_reviewers(cwd):
        return False
    return bool(prefix) or any(os.path.isfile(path) for path in agent_files(name, cwd))


# ---- parsing --------------


class Stream:
    """Character source for shlex. A comment ends before its newline, which stays a separator."""

    def __init__(self, text):
        self.text = text
        self.position = 0

    def read(self, count=1):
        chunk = self.text[self.position : self.position + count]
        self.position += len(chunk)
        return chunk

    def readline(self):
        # shlex calls this after it read a '#'. Inside a word ($#, ${#a[@]}) that is no comment:
        # consume nothing, so the word just ends there.
        if self.position >= 2 and self.text[self.position - 2] not in WORD_BREAKS:
            return ""
        end = self.text.find("\n", self.position)
        end = len(self.text) if end < 0 else end
        line = self.text[self.position : end]
        self.position = end
        return line


def skip_heredoc_bodies(text, heredocs):
    """Drop the lines of each heredoc body, up to and including its delimiter line."""
    lines = text.split("\n")
    index = 0
    for delimiter, strip_tabs in heredocs:
        while index < len(lines):
            line = lines[index].lstrip("\t") if strip_tabs else lines[index]
            index += 1
            if line == delimiter:
                break
    return "\n".join(lines[index:])


def events(text):
    """The shell line as a list of simple commands (token lists) and "(" / ")" markers. ValueError if unparsable.

    Redirections are dropped (operator, target and a file-descriptor digit before it); heredoc bodies are skipped.
    """
    text = text.replace("\\\n", " ")
    result, current = [], []
    while text:
        stream = Stream(text)
        lexer = shlex.shlex(stream, posix=True, punctuation_chars=PUNCTUATION)
        lexer.whitespace = " \t\r"
        # With punctuation_chars, shlex splits words at these; keep $VAR, URLs and refnames (a@{u}, v:refname) whole.
        lexer.wordchars += "$:@%+,{}[]^!"
        # previous: the raw text after a heredoc operator, else None. skip_target: the next word is a redirect target.
        heredocs, previous, arithmetic, skip_target = [], None, 0, False
        text = ""
        while True:
            # shlex reads one character ahead and pushes it back; _pushback_chars is private
            # (a test pins it in no-global-install's test), and if it ever goes away main() fails open.
            start = stream.position - len(lexer._pushback_chars)
            token = lexer.get_token()
            if token is None:
                break
            # A quoted token ('<<', ';') is a word, not an operator: only raw text counts.
            raw = stream.text[start:].lstrip(" \t\r")
            while raw.startswith("#"):
                hash_index = len(stream.text) - len(raw)
                if hash_index == 0 or stream.text[hash_index - 1] in WORD_BREAKS:
                    raw = raw[raw.find("\n") if "\n" in raw else len(raw) :]
                else:
                    raw = raw[1:].lstrip(" \t\r")
            operator = raw.startswith(token)
            if operator and token and token[0] in SEPARATOR_CHARACTERS:
                lead = token[: len(token) - len(token.lstrip(";&|\n()"))]
                arithmetic = max(0, arithmetic + lead.count("((") - lead.count("))"))
                skip_target = False
                if current:
                    result.append(current)
                current = []
                result.extend(character for character in lead if character in "()")
                if "\n" in lead and heredocs:
                    body = stream.text.find("\n", start) + 1
                    text = skip_heredoc_bodies(stream.text[body:], heredocs)
                    break
            elif previous is not None:
                strip_tabs = previous.startswith("-") and token.startswith("-")
                delimiter = token[1:] if strip_tabs else token
                if delimiter:
                    heredocs.append((delimiter, strip_tabs))
            elif operator and token == "<<":
                pass  # the heredoc operator itself; its delimiter is read next
            elif operator and token and set(token) <= set("<>&"):
                skip_target = True
                operator_index = len(stream.text) - len(raw)
                digits = current[-1] if current else ""
                if (
                    digits.isdigit()
                    and stream.text[operator_index - len(digits) : operator_index] == digits
                ):
                    before = operator_index - len(digits) - 1
                    if before < 0 or stream.text[before] in WORD_BREAKS:
                        current.pop()
            elif skip_target:
                skip_target = False
            else:
                current.append(token)
            previous = None
            if operator and token == "<<" and not arithmetic:
                previous = raw[2:]
    if current:
        result.append(current)
    return result


def is_assignment(token):
    name, equals, _ = token.partition("=")
    return bool(equals) and name.replace("_", "a").isalnum() and not name[0].isdigit()


def unwrap(tokens):
    """(assignments, program tokens) with keywords and sudo-like prefixes (and their options) removed."""
    assignments, index = {}, 0
    while index < len(tokens):
        word = tokens[index]
        if word in KEYWORDS:
            index += 1
        elif is_assignment(word):
            name, _, value = word.partition("=")
            assignments[name] = value
            index += 1
        elif word in PREFIXES:
            index += 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 2 if tokens[index] in OPTIONS_WITH_VALUE.get(word, ()) else 1
        else:
            break
    return assignments, tokens[index:]


def shell_payload(tokens):
    """The command string of `bash -c` (or -lc, ...), else None."""
    if tokens[0].rsplit("/", 1)[-1] not in SHELLS:
        return None
    for index, word in enumerate(tokens[1:], 1):
        if not word.startswith("-"):
            return None
        if not word.startswith("--") and "c" in word:
            return tokens[index + 1] if index + 1 < len(tokens) else None
    return None


# ---- where git runs ----------------------------------------------------------------------------------------------


def unknown(path):
    return path is None or any(mark in path for mark in "$`*?")


def join(base, path):
    """`path` resolved against `base`; None when it cannot be known."""
    if unknown(path) or path == "-":
        return None
    path = os.path.expanduser(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(base, path)) if base else None


class Repositories:
    """Answers "is this a real (not temp-dir) repository?", caching git's answers for the run."""

    def __init__(self):
        # /tmp and /var/tmp too: tempfile.gettempdir() follows TMPDIR, and macOS keeps its own under /var/folders.
        self.temporaries = {
            os.path.realpath(d) for d in (tempfile.gettempdir(), "/tmp", "/var/tmp")
        }
        self.cache = {}

    def under_temporary(self, path):
        path = os.path.realpath(path)
        return any(path == t or path.startswith(t + os.sep) for t in self.temporaries)

    def real(self, directory, git_dir=None):
        """True / False, or None when it cannot be told (not a repository, no git, unknown path)."""
        if git_dir is not None and unknown(git_dir):
            return None
        if directory is None and git_dir is not None and os.path.isabs(git_dir):
            directory = os.sep  # an absolute GIT_DIR does not depend on where the line is
        if directory is None:
            return None
        key = (directory, git_dir)
        if key not in self.cache:
            self.cache[key] = self._ask(directory, git_dir)
        return self.cache[key]

    def _ask(self, directory, git_dir):
        while not os.path.isdir(directory):
            parent = os.path.dirname(directory)
            if parent == directory:
                return None
            directory = parent
        environment = {k: v for k, v in os.environ.items() if k not in GIT_ENVIRONMENT}
        if git_dir is not None:
            environment["GIT_DIR"] = git_dir
        try:
            completed = subprocess.run(
                ["git", "rev-parse", "--git-common-dir"],
                cwd=directory,
                env=environment,
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        output = completed.stdout.strip()
        if completed.returncode != 0 or not output:
            return None
        return not self.under_temporary(os.path.join(directory, output))


class State:
    def __init__(self, cwd, environment=None):
        self.cwd = cwd
        self.environment = dict(environment or {})

    def copy(self):
        return State(self.cwd, self.environment)


def git_invocation(tokens, state, assignments):
    """(subcommand, arguments, git dir, work tree, working directory) of a git command line; subcommand may be None."""
    git_dir = assignments.get("GIT_DIR", state.environment.get("GIT_DIR"))
    work_tree = assignments.get("GIT_WORK_TREE", state.environment.get("GIT_WORK_TREE"))
    directory, index = state.cwd, 1
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        name, equals, value = option.partition("=")
        if option == "-C":
            directory = join(directory, tokens[index + 1]) if index + 1 < len(tokens) else None
            index += 2
        elif name in {"--git-dir", "--work-tree"}:
            if not equals:
                value = tokens[index + 1] if index + 1 < len(tokens) else None
                index += 1
            if name == "--git-dir":
                git_dir = value
            else:
                work_tree = value
            index += 1
        elif option in GIT_OPTIONS_WITH_VALUE:
            index += 2
        else:
            index += 1
    if index >= len(tokens):
        return None, [], git_dir, work_tree, directory
    return tokens[index], tokens[index + 1 :], git_dir, work_tree, directory


# ---- git: the allow-list -----------------------------------------------------------------------------------------


def positionals(arguments, value_options):
    result, index = [], 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--":
            result.extend(arguments[index + 1 :])
            break
        if argument in value_options:
            index += 2
            continue
        if not argument.startswith("-"):
            result.append(argument)
        index += 1
    return result


def lists_only(arguments, short_flags, listing_letters, value_options):
    """branch/tag: True when the arguments only list (no name to create, no delete/move/force flag)."""
    names, index, listing = [], 0, False
    while index < len(arguments):
        argument = arguments[index]
        name = argument.partition("=")[0]
        if name in value_options:
            index += 1 if "=" in argument else 2
            continue
        if argument.startswith("--"):
            if name not in LIST_FLAGS:
                return False
            listing = listing or name in {"--list", "--show-current", "--verify"}
        elif argument.startswith("-") and len(argument) > 1:
            letters = re.sub(r"n[0-9]*", "", argument[1:])  # tag -n5, -ln5
            if not set(letters) <= short_flags:
                return False
            listing = listing or bool(set(letters) & listing_letters)
        else:
            names.append(argument)
        index += 1
    return listing or not names


LIST_FLAGS = {
    "--all", "--remotes", "--verbose", "--list", "--show-current", "--verify", "--no-color", "--color", "--no-column",
    "--column", "--ignore-case", "--no-abbrev", "--abbrev", "--contains", "--no-contains", "--merged", "--no-merged",
    "--points-at", "--sort", "--format",
}  # fmt: skip


def fetch_is_read(arguments):
    names = positionals(arguments, FETCH_VALUE_OPTIONS)
    return not any(":" in refspec for refspec in names[1:])


def config_is_read(arguments):
    if any(flag in CONFIG_WRITE_FLAGS for flag in arguments):
        return False
    names = positionals(arguments, CONFIG_VALUE_OPTIONS)
    # `config get|list ...`, `config --get key`, `config --list`, and `config key` (one name, no value).
    return (
        names[:1] in (["get"], ["list"])
        or len(names) <= 1
        or any(flag in CONFIG_READ_FLAGS for flag in arguments)
    )


def git_is_read(subcommand, arguments):
    if subcommand in READ_SUBCOMMANDS or asks_help(arguments):
        return True
    if subcommand == "format-patch":
        return "--stdout" in arguments
    positional_arguments = positionals(arguments, set())
    if subcommand == "symbolic-ref":
        return len(positional_arguments) == 1 and not {"-d", "--delete"} & set(arguments)
    if subcommand == "hash-object":
        return "-w" not in arguments
    if subcommand == "submodule":
        return positional_arguments[:1] in ([], ["status"], ["summary"])
    if subcommand == "notes":
        return positional_arguments[:1] in ([], ["show"], ["list"])
    if subcommand == "bundle":
        return positional_arguments[:1] in (["verify"], ["list-heads"])
    if subcommand == "branch":
        return lists_only(arguments, BRANCH_FLAGS, {"l"}, LISTING_VALUE_OPTIONS)
    if subcommand == "tag":
        return lists_only(arguments, TAG_FLAGS, {"l", "v"}, LISTING_VALUE_OPTIONS)
    if subcommand == "config":
        return config_is_read(arguments)
    if subcommand == "remote":
        return all(
            argument in {"-v", "--verbose"} for argument in arguments
        ) or positional_arguments[:1] in (["get-url"], ["show"])
    if subcommand == "stash":
        return positional_arguments[:1] in (["list"], ["show"])
    if subcommand == "apply":
        return "--apply" not in arguments and any(
            flag in arguments for flag in ("--check", "--stat", "--numstat", "--summary")
        )
    if subcommand == "fetch":
        return fetch_is_read(arguments)
    if subcommand == "worktree":
        return positional_arguments[:1] == ["list"]
    if (
        subcommand == "init"
    ):  # a re-init is harmless, but --separate-git-dir moves the repository's git dir
        return not any(argument.partition("=")[0] == "--separate-git-dir" for argument in arguments)
    if subcommand == "reflog":
        return not {"expire", "delete"} & set(positional_arguments[:1])
    if subcommand == "fsck":
        return "--lost-found" not in arguments
    return False


def git_reason(tokens, state, assignments, repositories):
    if (
        len(tokens) > 1 and tokens[1] in HELP_FLAGS
    ):  # `git --help commit`, `git -h`: the manual or the usage
        return None
    subcommand, arguments, git_dir, work_tree, directory = git_invocation(
        tokens, state, assignments
    )
    if subcommand is None or git_is_read(subcommand, arguments):
        return None
    work_directory = join(directory, work_tree) if work_tree else None
    answers = [repositories.real(directory, git_dir)]
    if work_tree and not unknown(work_tree):
        answers.append(repositories.real(work_directory))
    return GIT_REASON if any(answer is True for answer in answers) else None


# ---- gh ---------------------------------------------------------------------------------------------------------


def gh_reason(tokens):
    words, positions, index = [], [], 1
    while index < len(tokens) and len(words) < 3:
        argument = tokens[index]
        if argument in GH_OPTIONS_WITH_VALUE:
            index += 2
            continue
        if not argument.startswith("-"):
            words.append(argument)
            positions.append(index)
            if argument == "api" and len(words) == 1:
                break
        index += 1
    group, action, third = (words + ["", "", ""])[:3]
    if group == "api":
        return GH_REASON if api_writes(tokens[positions[0] + 1 :]) else None
    if positions and asks_help(tokens[positions[0] + 1 :]):
        return None
    if (group == "pr" and action in GH_PR_WRITES) or (
        group == "issue" and action in GH_ISSUE_WRITES
    ):
        return GH_REASON
    if group and gh_action_writes(group, action, third):
        return GH_REASON
    return None


def gh_action_writes(group, action, third):
    def writes(word):
        return word in GH_ANY_GROUP_WRITES or (
            word.startswith(GH_WRITE_PREFIXES) and not word.endswith(GH_READ_SUFFIXES)
        )

    return (
        writes(action)
        or (group == "label" and action == "clone")
        or (action in GH_SUBGROUPS and writes(third))
    )


def api_writes(arguments):
    """True when the arguments after `gh api` choose a method other than GET, or send fields to a non-graphql endpoint."""
    method, endpoint, fields = None, None, False
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        name = argument.partition("=")[0]
        if argument in {"-X", "--method"} and index + 1 < len(arguments):
            method = arguments[index + 1]
            index += 1
        elif name == "--method":
            method = argument.partition("=")[2]
        elif argument.startswith("-X") and len(argument) > 2:
            method = argument[2:]
        elif argument in GH_API_OPTIONS_WITH_VALUE:
            index += 1
        elif argument in GH_FIELD_FLAGS or name in {"--field", "--raw-field", "--input"}:
            fields = True
            index += 1 if "=" not in argument else 0
        elif not argument.startswith("-") and endpoint is None:
            endpoint = argument
        index += 1
    if method is not None:
        return method.upper() != "GET"
    return fields and endpoint != "graphql"


# ---- the scan -----------------------------------------------------------------------------------------------------


def program_of(tokens):
    return tokens[0].rsplit("/", 1)[-1]


def scan(command, state, repositories, depth=0):
    """The first refused command in a shell line as (tokens, reason), else None."""
    stack = []
    for item in events(command):
        if item == "(":
            stack.append(state.copy())
            continue
        if item == ")":
            if stack:
                state = stack.pop()
            continue
        assignments, tokens = unwrap(item)
        if not tokens:
            state.environment.update(
                assignments
            )  # a bare `GIT_DIR=x` lasts for the rest of the line
            continue
        program = program_of(tokens)
        if program == "export":
            for word in tokens[1:]:
                if is_assignment(word):
                    name, _, value = word.partition("=")
                    state.environment[name] = value
        elif program == "unset":
            for word in tokens[1:]:
                state.environment.pop(word, None)
        elif program in {"cd", "pushd"}:
            arguments = [word for word in tokens[1:] if not word.startswith("-") or word == "-"]
            state.cwd = join(state.cwd, arguments[0]) if arguments else os.path.expanduser("~")
        elif program == "popd":
            state.cwd = None
        elif (payload := shell_payload(tokens)) is not None:
            if depth < 3:
                found = scan(
                    payload,
                    State(state.cwd, {**state.environment, **assignments}),
                    repositories,
                    depth + 1,
                )
                if found:
                    return found
        elif program == "git":
            why = git_reason(tokens, state, assignments, repositories)
            if why:
                return tokens, why
        elif program == "gh":
            why = gh_reason(tokens)
            if why:
                return tokens, why
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        agent_type = payload.get("agent_type")
        if not agent_type or not isinstance(agent_type, str):
            return 0
        if payload.get("tool_name", "Bash") != "Bash":
            return 0
        command = payload["tool_input"]["command"]
        if not isinstance(command, str) or ("git" not in command and "gh" not in command):
            return 0
        cwd = payload.get("cwd")
        cwd = cwd if isinstance(cwd, str) and cwd else os.getcwd()
        if not is_reviewer(agent_type, cwd):
            return 0
        found = scan(command, State(os.path.normpath(cwd)), Repositories())
    except (ValueError, KeyError, TypeError, AttributeError, OSError):
        return 0
    if found:
        tokens, why = found
        print(
            f"reviewer-guard (review-routing): blocked `{shlex.join(tokens)}` for a reviewer. {why}",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
