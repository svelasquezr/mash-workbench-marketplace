"""Import guards: files reachable from a guarded module that lack its reviewer."""

import ast
from collections import deque
from pathlib import Path

from route_rules import reviewers_for_path
from route_types import Config, ImportGuard


def module_file(module: str, guard: ImportGuard, repository_root: Path) -> Path | None:
    """The project's file for a module (a.b -> <dir>/a/b/__init__.py, else <dir>/a/b.py: a
    package wins over a module of the same name, as when Python imports it); None for
    a module outside the source folders (the standard library, a dependency) or a name inside one
    (`from a import b` where b is a function)."""
    parts = module.split(".")
    for source_dir in guard.source_dirs:
        base = repository_root / source_dir / Path(*parts)
        for candidate in (base / "__init__.py", base.with_suffix(".py")):
            if candidate.is_file():
                return candidate
    return None


def imported_names(source_file: Path, module: str) -> set[str]:
    """Every module name a file imports, read with ast (nothing runs). `from a import b` yields
    a and a.b (b may be a module); a relative import is resolved against the file's package."""
    tree = ast.parse(source_file.read_bytes(), filename=str(source_file))
    package = module.split(".") if source_file.name == "__init__.py" else module.split(".")[:-1]
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                if node.level - 1 >= len(package):
                    continue  # beyond the top-level package: Python refuses it too
                base = package[: len(package) - (node.level - 1)]
                prefix = ".".join([*base, *([node.module] if node.module else [])])
            else:
                prefix = node.module or ""
            if prefix:
                names.add(prefix)
            names.update(
                f"{prefix}.{alias.name}" if prefix else alias.name
                for alias in node.names
                if alias.name != "*"
            )
    return names


def walk_guard(
    guard: ImportGuard, repository_root: Path
) -> tuple[dict[str, tuple[str, ...]], list[str]]:
    """The project files the guard's entry modules load, each with an import chain from an entry
    module (importing a.b.c also runs a/__init__.py and a/b/__init__.py), and the problems found:
    a missing entry module, a file that doesn't parse."""
    files: dict[str, tuple[str, ...]] = {}
    problems: list[str] = []
    pending: deque[tuple[str, tuple[str, ...]]] = deque()
    for entry_module in guard.entry_modules:
        if module_file(entry_module, guard, repository_root) is None:
            problems.append(
                f"entry module {entry_module} not found under {', '.join(guard.source_dirs)}"
            )
        else:
            pending.append((entry_module, (entry_module,)))
    seen: set[str] = set()
    while pending:
        module, chain = pending.popleft()
        if module in seen:
            continue
        seen.add(module)
        parts = module.split(".")
        pending.extend(
            (".".join(parts[:count]), (*chain[:-1], ".".join(parts[:count])))
            for count in range(1, len(parts))
        )
        source_file = module_file(module, guard, repository_root)
        if source_file is None:
            continue
        relative_path = source_file.relative_to(repository_root).as_posix()
        if relative_path in files:
            continue
        files[relative_path] = chain
        try:
            names = imported_names(source_file, module)
        except (SyntaxError, UnicodeDecodeError, ValueError, OSError) as error:
            problems.append(f"could not parse {relative_path} to follow its imports: {error}")
            continue
        pending.extend((name, (*chain, name)) for name in sorted(names) if name not in seen)
    return files, problems


def guard_problems(guard: ImportGuard, config: Config, repository_root: Path) -> list[str]:
    files, problems = walk_guard(guard, repository_root)
    walk_complete = not problems
    for file_path, chain in sorted(files.items()):
        reviewed = guard.reviewer in reviewers_for_path(file_path, config)
        if not reviewed and not any(allow.matches(file_path) for allow in guard.allow):
            problems.append(
                f"{file_path} is on the path (via {' → '.join(chain)}) but {guard.reviewer}"
                " doesn't review it: route it to them, or add it to allow with a reason"
            )
    for allow in guard.allow if walk_complete else ():
        reached = [file_path for file_path in files if allow.matches(file_path)]
        if not reached:
            problems.append(f"allow {allow.describe()} is stale: nothing on the path matches it")
        elif all(guard.reviewer in reviewers_for_path(file_path, config) for file_path in reached):
            problems.append(f"allow {allow.describe()} is stale: {guard.reviewer} reviews it now")
    return [f"import_guards ({guard.name}): {problem}" for problem in problems]


def guard_chains(
    changed_paths: list[str], config: Config, repository_root: Path
) -> list[tuple[str, str, tuple[str, ...]]]:
    """(path, guard name, import chain) for each changed path an import guard's path loads."""
    found = []
    for guard in config.import_guards:
        files, _ = walk_guard(guard, repository_root)
        found += [
            (path, guard.name, files[path])
            for path in dict.fromkeys(changed_paths)
            if path in files
        ]
    return found
