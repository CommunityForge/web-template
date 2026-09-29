# Restating a change for a fresh chat

Reached from the **Thrash** row: many rounds, fixes undoing fixes, a chat that has stopped
converging. Long chats get worse at this, and the cure is a fresh one with a crisp restatement,
not another round here.

## Say it plainly first

One sentence, no softening: the chat has gone round enough times that a fresh one will do better
than another try here. Then offer the restatement below. The person decides.

## The restatement

Write it for them, ready to paste. Five parts, each one line or a short list, in product words:

```
Change: <name>  (branch <branch>, preview <link if any>)

Works now: <the parts of the change they have seen working>

The one thing wrong: <did / expected / saw, one line>

Already tried, and what each one broke:
- <attempt> -> <what it undid>
- <attempt> -> <what it undid>

Done looks like: <one observable sentence a reviewer could disagree with>
```

Where the facts come from:

- **Works now** and **the one thing wrong**: the person's words, confirmed by asking; the spec's
  scenarios (`openspec/changes/<name>/specs/**/spec.md`) supply the vocabulary.
- **Already tried**: `git log --oneline` on the change's branch since the last task was checked,
  read for the fix-type commits, plus what the person remembers. Attempts that undid each other are
  the whole point of this list; name the pairs.
- **Done looks like**: the THEN of the scenario that is failing. If no scenario covers it, that is
  the finding: the change is drifting, and the **Drift** row applies instead.

## Three strikes

The same thing coming back three times is not a bug report problem; it is a plan too big or too
vague for one pass. Say so, and route to the smaller plan:

- Not merged: new chat, `/opsx:update <name>`, and shrink the change to the part that works plus the
  one thing wrong. Then new chat, `/WriteCode <name>`.
- Merged or filed: finish what works with `/UpdateDocs`, then a new, smaller change with
  `/DefineFeature` in a new chat.
