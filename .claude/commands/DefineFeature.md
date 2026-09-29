---
description: Define a feature
---

Follow the instructions in @.claude/commands/opsx/propose.md exactly, with one amendment to its
**Output** section:

After completing all artifacts, do not enumerate artifacts, files, or paths. Instead:

- Give a short plain-language summary of what the proposed change will let the person do, and
  name the change folder once so it can be referred to later.
- Then, once the person has nothing further to add and every open question is settled, end with
  exactly this sentence and nothing after it:

  "When you are satisfied with the specification, begin a new chat and use `/WriteCode` to
  realize the changes."

Beginning a new chat before `/WriteCode` is mandatory, not a suggestion — a hook blocks
`/WriteCode` in this chat. Never offer to apply the change from this chat.

The one exception is a cloud session, where a new chat starts from a fresh checkout and the
proposal would be lost. Check with `echo "$CLAUDE_CODE_REMOTE"`; if it prints `true`, end instead
with exactly this sentence and nothing after it:

"When you are satisfied with the specification, use `/WriteCode` in this chat to realize the
changes."

ARGUMENTS: $ARGUMENTS
