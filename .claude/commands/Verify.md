---
description: Check a built feature against its plan
---

Follow the instructions in @.claude/commands/opsx/verify.md exactly, with one amendment.

**Amendment — the ending.** The report stays as written, down to its **Final Assessment**. After
it, add the next step in the person's words, chosen by that assessment:

- Ready for archive: "When you have tested it and everything works the way you expect, use
  `/UpdateDocs` to file this change away."
- Critical issues: one or two plain sentences on what the built change is still missing, then
  "Begin a new chat and use `/WriteCode <name>` to finish it, and `/Verify <name>` again after."
- Checks not verified and nothing critical: one plain sentence on what could not be checked and
  why, then the `/UpdateDocs` sentence above.

ARGUMENTS: $ARGUMENTS
