# What to try first

Reached from the **previewing** row when the person has not tried the preview yet. The handoff
gives the preview link and three concrete steps at most, in product words, so the person knows
where to click before they know what the change was.

## Derive, don't invent

1. Read the change's spec deltas (`openspec/changes/<name>/specs/**/spec.md`, or the archived copy
   under `openspec/changes/archive/` when the change is filed) and its `tasks.md`.
2. Take the first requirement's happy-path scenario: its WHEN is the action, its THEN is what they
   should see. That is step one.
3. Take the empty or first-use scenario if the spec has one: what they see with nothing there yet.
   That is step two, and it often comes first in time.
4. Take one failure or undo scenario: the mistake the change is supposed to survive. Step three.

Three steps, each naming the actual screen, button or field from the scenario. A scenario with no
visible THEN yields no step; skip it rather than paraphrase it.

## Shape

```
Preview: <link>

Try first:
1. Open <screen>, <do the WHEN>. You should see <the THEN>.
2. <empty case>
3. <failure or undo case>
```

Then the sentence the previewing row ends on when they come back happy:
"When you have tested it and everything works the way you expect, use `/UpdateDocs` to file this
change away."

## When the preview link is missing

`pr.N.preview_url=none` with the checks still `pending`: the preview is still building; say so and
give the pull request link, where the `## Preview 🔶` comment will appear. With the checks `fail`,
the **Broken** rows apply instead of this file.
