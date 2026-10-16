---
description: Describe a problem
---

Follow the instructions in @.claude/commands/opsx/explore.md exactly, with four amendments.

**Amendment 1 — the stance.** Replace the whole **The Stance** section with the role and voice in
@.claude/prompts/describe-problem.md, and speak from it for the entire conversation. Everything
else in explore mode stands: look things up before asking, run read-only commands freely, keep
every diagram ASCII, follow the guardrails. That file is the swappable part of this command: a
different role goes in that file, and this one does not change.

**Amendment 2 — where the documents live.** The role speaks of the organization's context documents
and its written-up solution. In this project those are:

- `docs/context/`: how the work is done today. Read its `README.md` index and open only the files
  whose line bears on what the person brought; never load the folder whole.
- `openspec/specs/`: what the app already does. Take the inventory with `openspec list --specs` and
  read the related capabilities in full, as explore mode describes.
- `openspec/changes/<name>/`: a feature being defined or built. When one is relevant, its
  `proposal.md` and `specs/*/spec.md` are the solution description the role reasons from.

Ground every design conversation in these. A question the files already answer is never asked.

**Amendment 3 — the handoff.** Of the four guides the role names, only the Spec Definer exists here,
and it is `/DefineFeature`. When the behavioral goal and the chosen interaction have crystallized
and the person has nothing further, end with exactly this sentence and nothing after it:

"When you are ready to turn this into a feature, use `/DefineFeature` in this chat."

Same chat, ON PURPOSE: nothing here is written to disk, so what was understood travels only through
the conversation. The phase guard allows it, since defining is the first stage of the cycle and
nothing has run yet.

**Amendment 4 — write nothing.** Explore mode may capture insights into change artifacts within a
confirmed scope; this command does not. It reads, draws and talks, and never creates a change, an
artifact, or a file. Anything worth keeping is said in the conversation and carried into
`/DefineFeature`.

ARGUMENTS: $ARGUMENTS
