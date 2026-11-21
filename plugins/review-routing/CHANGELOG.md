# Changelog

Newest first. "Changed scripts" lists the scripts and hooks whose behavior changed, so you know what to re-read before you update.

## 0.3.3 - 2026-11-21

Changed scripts:

- Removed the hook `hooks/haiku-reviewer-guard.py` and its `Agent|Task` entry in `hooks/hooks.json`. The plugin no longer blocks an Agent call that starts a reviewer on Haiku.
- `hooks/reviewer-guard.py`: no change in behavior (only its docstring changed).

Other:

- The router never prints Haiku, and `review-changes` tells the session to use the models it prints. Nothing checks a direct dispatch or a fix-round dispatch any more.
- The README, the `inspect` skill and the `add-reviewer` reference now say that the router, not a hook, keeps Haiku out.
- Added this changelog.
