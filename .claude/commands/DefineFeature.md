---
description: Define a feature
---

Follow the instructions in @.claude/commands/opsx/propose.md exactly, with three amendments.

**Amendment 1 — save the proposal in a cloud session.** Check with `echo "$CLAUDE_CODE_REMOTE"`. If
it prints `true`, the checkout is temporary and a new chat will not see it, so once every artifact
is written and every open question is settled: commit the change folder with a conventional message
(`docs(openspec): propose <name>`) and push the session's branch, `git push -u origin <branch>`. Open
no pull request: a push is a save, a pull request is a review. Locally nothing is committed here;
the disk is durable and `/WriteCode` publishes later.

**Amendment 2 — the Output section.** After completing all artifacts, do not enumerate artifacts,
files, or paths. Instead:

- Give a short plain-language summary of what the proposed change will let the person do, and
  name the change folder once so it can be referred to later.
- Every message that ends with a `/WriteCode` sentence below lists, before that sentence and in
  full, every ASSUMED line from the change's `discovery.md`, re-read from disk, in plain chat text
  — never inside a question tool. If `discovery.md` records none, say in one line that nothing was
  assumed. The person approves the assumptions by moving on, so they must see them first.
- Then, once the person has nothing further to add and every open question is settled, end with
  exactly this sentence and nothing after it:

  "When you are satisfied with the specification, begin a new chat and use `/WriteCode` to
  realize the changes."

Beginning a new chat before `/WriteCode` is mandatory, not a suggestion — a hook blocks
`/WriteCode` in this chat. Never offer to apply the change from this chat.

The one exception is a cloud session (`CLAUDE_CODE_REMOTE` printed `true` above), where a new chat
starts from a fresh checkout. There, after the save in amendment 1, end instead with exactly this
sentence and nothing after it:

"When you are satisfied with the specification, use `/WriteCode` in this chat to realize the
changes."

**Amendment 3 — show the documents, not the diff.** The person cannot read a diff, and revising a
file in place shows them nothing else. So every turn that creates or changes `proposal.md` or any
`specs/*/spec.md` in the change ends, before its closing message, by sending each of those files
changed that turn with `SendUserFile` (`display: "render"`, `status: "normal"`). The first draft
sends all of them; a revision sends only the ones it touched. Never send `discovery.md`,
`design.md` or `tasks.md`: they are not written for the person. If `SendUserFile` is unavailable,
name each changed document in plain words instead of pointing at the diff.

ARGUMENTS: $ARGUMENTS
