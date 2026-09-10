---
description: Propose a change
---

Follow the instructions in @.claude/commands/opsx/propose.md exactly, with one amendment to its
**Output** section:

After completing all artifacts, do not enumerate artifacts, files, or paths. Instead:

- Give a short plain-language summary of what the proposed change will let the person do, and
  name the change folder once so it can be referred to later.
- Then, once the person has nothing further to add and every open question is settled, end with
  exactly this sentence and nothing after it:

  "When you are satisfied with the specification, begin a new chat and use `/apply` to realize
  the changes."

Beginning a new chat before `/apply` is mandatory, not a suggestion — a hook blocks `/apply` in
this chat. Never offer to apply the change from this chat.

ARGUMENTS: $ARGUMENTS
