---
name: review-<topic>
description: Use when reviewing a change that <what the change does, in words: adds or edits an Angular component, its template, or its inputs and outputs>
---

# Review: <topic, in words>

<For a companion: Load the `<builder skill name>` skill and check the change against it. For a standalone standard: one sentence on what this covers and why a mistake here is expensive.>

<!-- Model: the review runs this standard on sonnet. Only when its checks need deep reasoning across files, add a body line "Model: opus" (or "fable") here; the review skill reads it. It is not frontmatter: the frontmatter holds only name and description (this plugin's convention). Delete this comment. -->

## Project checks

<!-- Each line is an instruction a reviewer can follow on a diff, specific to this project: the invariant, where it holds, and the near miss that looks wrong but is fine. A check from an escape ends with (escape: <link>, <YYYY-MM-DD>). Delete this comment. -->

- <check>
- A new branch in <topic> code has a test for the case it handles and for a near miss it must not.

## Not checked here

- <what a tool enforces, and the tool: formatting and import order, the formatter and the linter>
