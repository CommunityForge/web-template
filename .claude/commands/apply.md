---
description: Apply a change
---

Follow the instructions in @.claude/commands/opsx/apply.md exactly, with one amendment to its
**Output On Completion** section — replace that block (the change/schema/progress header and the
per-task checklist; the checklist already lives on disk in `tasks.md`) with a plain-language
testing handoff:

- "Ready for you to test." plus one line on what is different now, in terms of what the person
  can do or see.
- What to try first, concretely — name the actual screen, button, or action, drawn from the
  change's own spec and tasks. Never say "run the tests".
- End with exactly this sentence and nothing after it:

  "When you have tested it and everything works the way you expect, use `/archive` to file this
  change away."

The **Output On Pause (Issue Encountered)** behavior is unchanged.

ARGUMENTS: $ARGUMENTS
