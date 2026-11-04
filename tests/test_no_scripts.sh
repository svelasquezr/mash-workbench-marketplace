# shellcheck shell=bash
# Policy (docs/decisions/0004-no-shipped-scripts.md): the plugins ship no scripts. Everything under plugins/ is
# Markdown, JSON or TOML (plus LICENSE), nothing is executable, no text tells Claude to run a file the plugin
# ships, and the only hook is review-routing's inline Haiku guard. Shipped text also carries no hidden Unicode
# (zero-width, bidirectional or tag characters can hide instructions from a human reviewer) and links only to
# github.com and code.claude.com. The plugin-safety-reviewer agent judges what this test cannot.
# shellcheck disable=SC2016  # the fixtures hold literal Markdown and shell text on purpose
set -euo pipefail
source tests/lib.sh
temporary_directory=$(mktemp -d); trap 'rm -rf "$temporary_directory"' EXIT

# shipped_content_problems <repository>: one line per broken rule for the files git tracks under plugins/.
shipped_content_problems() {
  python3 - "$1" <<'PY'
import json, re, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
listing = subprocess.run(["git", "-C", str(root), "ls-files", "-s", "--", "plugins"],
                         capture_output=True, text=True, check=True).stdout
problems = []
allowed_suffixes = {".md", ".json", ".toml"}
invocation = re.compile(
    r"\b(?:bash|sh|zsh|dash|python3?|node|deno|bun|ruby|perl|pwsh|powershell)\s+(?:<[^>\n]*>)?[^\s`'\"]*\.(?:sh|py|js|mjs|cjs|ts|rb|pl|ps1)\b"
    r"|\$\{?CLAUDE_(?:PLUGIN_ROOT|SKILL_DIR)\}?/[^\s`'\"]*\.(?:sh|py|js|mjs|cjs|ts|rb|pl|ps1)\b"
)
hidden = re.compile("[\u200b\u200c\u200d\u2060\ufeff\u202a-\u202e\u2066-\u2069\U000e0000-\U000e007f]")
url = re.compile(r"https?://[^\s)>\]`'\"]+")
allowed_hosts = ("github.com", "code.claude.com")
for line in listing.splitlines():
    meta, path = line.split("\t", 1)
    mode = meta.split()[0]
    name = Path(path).name
    if name != "LICENSE" and Path(path).suffix not in allowed_suffixes:
        problems.append(f"{path}: only Markdown, JSON, TOML and LICENSE ship in a plugin")
    if mode != "100644":
        problems.append(f"{path}: mode {mode}; nothing in a plugin is executable or a link")
    text = (root / path).read_text(encoding="utf-8", errors="replace")
    if text.startswith("#!"):
        problems.append(f"{path}: starts with a shebang")
    for match in invocation.finditer(text):
        problems.append(f"{path}: runs a file: {match.group(0)}")
    if hidden.search(text):
        problems.append(f"{path}: holds hidden Unicode (zero-width, bidirectional or tag characters)")
    for match in url.finditer(text):
        host = match.group(0).split("/")[2].lower()
        if host not in allowed_hosts:
            problems.append(f"{path}: links outside github.com and code.claude.com: {match.group(0)}")
    if path.endswith(".md"):
        # Claude Code runs !`command` and ```! fenced blocks when a skill loads. Flag everything its own patterns match
        # (as of 2.1.318: an inline !`...` after a line start or whitespace, possibly across lines, and ```! anywhere),
        # and, stricter, any code span that opens right after "!" wherever it sits. A span that merely contains "!"
        # (such as `:!`) is not flagged.
        claude_inline = re.search(r"(?:^|\s)!`[^`]+`", text, re.M)
        span_after_bang = any(text[m.start() - 1:m.start()] == "!" for m in re.finditer(r"`[^`\n]+`", text))
        if claude_inline or span_after_bang or "```!" in text:
            problems.append(f"{path}: uses the !`command` syntax, which runs a shell command when the file loads")
    # Frontmatter is allow-listed line by line, so no YAML trick (an explicit "? hooks" key, a lone carriage return as
    # a line break, quoted or escaped keys, anchors) can smuggle in a key such as hooks:, which runs commands.
    if name.lower() == "skill.md" and name != "SKILL.md":
        problems.append(f"{path}: name a skill file SKILL.md exactly")
    is_agent = re.fullmatch(r"plugins/[^/]+/agents/[^/]+\.md", path) is not None
    if name == "SKILL.md" or is_agent:
        allowed = ("name", "description") if name == "SKILL.md" else ("name", "description", "tools", "model", "effort")
        plain = r"[^\s#&*!|>'\"%@`{\[?,:\-](?:(?!: | #)[^\x00-\x1f\x7f\x85\u2028\u2029])*"
        quoted = r'"[^"\\\x00-\x1f\x7f\x85\u2028\u2029]*"' if is_agent else r"(?!)"
        line_rule = re.compile(rf"({'|'.join(allowed)}): (?:{plain}|{quoted})")
        head = text.split("---", 2)[1] if text.startswith("---\n") and text.count("---") >= 2 else None
        lines = [] if head is None else [line for line in head.split("\n") if line]
        keys = sorted(line.split(":", 1)[0] for line in lines)
        required = ["description", "name"]
        if head is None or any(not line_rule.fullmatch(line) for line in lines) or len(keys) != len(set(keys)) \
                or (name == "SKILL.md" and keys != required) or not set(required) <= set(keys):
            problems.append(f"{path}: frontmatter holds only {', '.join(allowed)}, one plain value per line")
    if name == ".mcp.json":
        problems.append(f"{path}: an MCP server runs a program")
    if name == "plugin.json":
        manifest = json.loads(text)
        for key in ("hooks", "mcpServers", "lspServers"):
            if key in manifest:
                problems.append(f"{path}: declares {key}")
    if name == "hooks.json":
        if path != "plugins/review-routing/hooks/hooks.json":
            problems.append(f"{path}: the only hook is review-routing's Haiku guard")
            continue
        hooks = json.loads(text)["hooks"]
        entries = [hook for event in hooks.values() for group in event for hook in group["hooks"]]
        if list(hooks) != ["PreToolUse"] or len(entries) != 1:
            problems.append(f"{path}: exactly one PreToolUse hook is allowed")
        for hook in entries:
            command = hook.get("command", "").replace("/dev/null", "")  # discarding output is not a file
            if hook.get("type") != "command" or re.search(r"(?:^|[\s;|&(<>\"'])(?:\.{1,2}|~|\$\{?\w+\}?)?/[^\s/]|\.(?:sh|py|js)\b|python|node|jq|curl|wget|\beval\b", command):
                problems.append(f"{path}: the hook must be an inline command that names no file, interpreter or network tool")
print("\n".join(problems))
PY
}

# fixture <name>: a git repository with one plugin that passes every rule; prints its path.
fixture() {
  local repository="$temporary_directory/$1"
  mkdir -p "$repository/plugins/p/skills/s" "$repository/plugins/p/.claude-plugin"
  printf -- '---\nname: s\ndescription: d\n---\n# Skill\n\nRun `git diff`. See https://github.com/o/r and https://code.claude.com/docs.\n' > "$repository/plugins/p/skills/s/SKILL.md"
  printf '{"name": "p"}\n' > "$repository/plugins/p/.claude-plugin/plugin.json"
  git -C "$repository" init -q && git -C "$repository" add -A
  echo "$repository"
}

# A clean plugin passes.
clean=$(fixture clean)
assert_eq "$(shipped_content_problems "$clean")" ""

# Each rule catches what it is for.
repository=$(fixture script); printf 'echo hi\n' > "$repository/plugins/p/skills/s/run.sh"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "run.sh: only Markdown, JSON, TOML and LICENSE"
repository=$(fixture executable); chmod +x "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "mode 100755"
repository=$(fixture shebang); printf '#!/bin/sh\n' > "$repository/plugins/p/skills/s/x.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "starts with a shebang"
repository=$(fixture invocation)
printf 'Run `python3 <this skill base directory>/route.py` then `bash ${CLAUDE_PLUGIN_ROOT}/x.sh`.\n' > "$repository/plugins/p/skills/s/y.md"
git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "runs a file: python3 <this"
assert_contains "$(shipped_content_problems "$repository")" "runs a file: bash \${CLAUDE_PLUGIN_ROOT}/x.sh"
repository=$(fixture hidden); printf 'Looks fine\xe2\x80\x8b.\n' > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "hidden Unicode"
repository=$(fixture tag); printf 'Tag\xf3\xa0\x81\x81.\n' > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "hidden Unicode"
repository=$(fixture link); printf 'Report to https://evil.example/collect?d=1\n' > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "links outside github.com"
repository=$(fixture mcp); printf '{}\n' > "$repository/plugins/p/.mcp.json"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "an MCP server runs a program"
repository=$(fixture manifest); printf '{"name": "p", "mcpServers": {}}\n' > "$repository/plugins/p/.claude-plugin/plugin.json"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "declares mcpServers"
repository=$(fixture other-hook); mkdir -p "$repository/plugins/p/hooks"
printf '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "exit 0"}]}]}}\n' > "$repository/plugins/p/hooks/hooks.json"
git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "the only hook is review-routing's Haiku guard"
repository=$(fixture script-hook); mkdir -p "$repository/plugins/review-routing/hooks"
printf '{"hooks": {"PreToolUse": [{"matcher": "Agent", "hooks": [{"type": "command", "command": "python3 \\"${CLAUDE_PLUGIN_ROOT}/hooks/g.py\\""}]}]}}\n' > "$repository/plugins/review-routing/hooks/hooks.json"
git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "must be an inline command"
repository=$(fixture two-hooks); mkdir -p "$repository/plugins/review-routing/hooks"
printf '{"hooks": {"PreToolUse": [{"matcher": "Agent", "hooks": [{"type": "command", "command": "exit 0"}, {"type": "prompt", "prompt": "x"}]}]}}\n' > "$repository/plugins/review-routing/hooks/hooks.json"
git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "exactly one PreToolUse hook"

repository=$(fixture inline-shell); printf 'Status: !`git status`\n' > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "runs a shell command when the file loads"
for form in '(!`curl x`)' '```!\ncurl x\n```' '- ```!\n  curl x\n  ```' '> ```!\n> curl x' 'Text ```!curl x``` here' \
  'Use a ` tick, then !`curl x`.' 'Run !`curl x\nmore`'; do
  repository=$(fixture "inline-$RANDOM"); printf -- "Text\n%b\n" "$form" > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
  assert_contains "$(shipped_content_problems "$repository")" "runs a shell command when the file loads"
done
# A code span that only contains "!" is fine; so is `a!`b`, which Claude Code does not run (it needs a line start or
# whitespace before the "!").
repository=$(fixture bang-in-span); printf 'Refuse a leading `:` other than `:!`, keep `a!b`.\n' > "$repository/plugins/p/skills/s/z.md"; git -C "$repository" add -A
assert_eq "$(shipped_content_problems "$repository")" ""
repository=$(fixture quoted-key)
printf -- '---\nname: s\ndescription: d\n"hooks": {}\n---\nBody.\n' > "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description"
repository=$(fixture escaped-key)
printf -- '---\nname: s\ndescription: d\n"\\x68ooks": {}\n---\nBody.\n' > "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description"
repository=$(fixture skill-hooks)
printf -- '---\nname: s\ndescription: d\nhooks: {}\n---\nBody.\n' > "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description"

for frontmatter in '? hooks\n: {}' 'description2: x\rhooks: {}' 'hooks: {PreToolUse: []}' 'name2: &h hooks'; do
  repository=$(fixture "frontmatter-$RANDOM")
  printf -- '---\nname: s\ndescription: d\n%b\n---\nBody.\n' "$frontmatter" > "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
  assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description"
done
repository=$(fixture cr-break); printf -- '---\nname: s\ndescription: d\rhooks: {}\n---\nBody.\n' > "$repository/plugins/p/skills/s/SKILL.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description"
repository=$(fixture lowercase); git -C "$repository" mv plugins/p/skills/s/SKILL.md plugins/p/skills/s/skill.md
assert_contains "$(shipped_content_problems "$repository")" "name a skill file SKILL.md exactly"
repository=$(fixture agent-hooks); mkdir -p "$repository/plugins/p/agents"
printf -- '---\nname: a\ndescription: "d"\nhooks: {}\nmodel: sonnet\n---\nBody.\n' > "$repository/plugins/p/agents/a.md"; git -C "$repository" add -A
assert_contains "$(shipped_content_problems "$repository")" "frontmatter holds only name, description, tools, model, effort"

# This repository's plugins follow every rule.
assert_eq "$(shipped_content_problems .)" ""
