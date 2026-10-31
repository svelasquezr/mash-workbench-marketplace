#!/usr/bin/env python3
"""PreToolUse hook for Agent (older name: Task): refuse a reviewer launched on Haiku.

Refuses (exit 2, reason on stderr, which Claude Code shows to Claude) when tool_input.model contains
"haiku" (case-insensitive, full model ids too) and the agent is a reviewer: subagent_type contains
"reviewer", or the prompt contains `SAFE TO LAND` or `Critical / Important / Minor`, or `NOT SAFE` together with `verdict` or `review`.
Pros of the heuristic: free and exact on what it sees; covers dispatches that bypass review-changes.
Cons: a reviewer briefed with neither marker gets through, and an unrelated prompt quoting a marker is refused.
A `haiku` in an agent file's frontmatter is invisible here; `route --check` and `route --models` refuse that.
Anything it cannot parse is allowed. Standard library only.
"""

import json
import re
import sys

PROMPT_MARKERS = ("SAFE TO LAND", "Critical / Important / Minor")


def is_reviewer(subagent_type: object, prompt: object) -> bool:
    if isinstance(subagent_type, str) and "reviewer" in subagent_type.lower():
        return True
    if not isinstance(prompt, str):
        return False
    if any(marker in prompt for marker in PROMPT_MARKERS):
        return True
    # `NOT SAFE` alone also appears in ordinary prose; it counts only next to a word that says this is a verdict.
    return "NOT SAFE" in prompt and re.search(r"verdict|review", prompt, re.IGNORECASE) is not None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        if payload.get("tool_name") not in {"Agent", "Task"}:
            return 0
        params = payload["tool_input"]
        model = params.get("model")
        if not isinstance(model, str) or "haiku" not in model.lower():
            return 0
        if not is_reviewer(params.get("subagent_type"), params.get("prompt")):
            return 0
    except (ValueError, KeyError, TypeError, AttributeError):
        return 0
    print(
        f"haiku-reviewer-guard (review-routing): blocked a reviewer launched on `{model}`."
        " Reviewers never run on Haiku, fix-round re-checks included."
        " Launch it again on the model that `reviewers-for-change.py <range> --models` printed for this agent"
        " (script in the review-changes skill directory of the review-routing plugin; `-` means pass no `model`)."
        " With no .claude/reviewers.toml, it prints the default reviewer and `-`: use the `model:` in the agent's frontmatter"
        " (Sonnet for review-routing:change-reviewer), or omit `model`."
        " The guard treats an agent as a reviewer when its subagent_type contains `reviewer`"
        " or its prompt contains `SAFE TO LAND` or `Critical / Important / Minor`, or `NOT SAFE` together with `verdict` or `review`.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
