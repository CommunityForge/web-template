---
description: Update the docs for a finished feature
---

Follow the instructions in @.claude/commands/opsx/archive.md exactly, with three amendments.

**Amendment 1 — the archive rides in the change's pull request.** The archive commit is what keeps
`main`'s specs and code landing together, so it goes on the branch the pull request is built from,
never on `main`:

1. Before archiving, be on the change's branch: the branch whose tree carries
   `openspec/changes/<name>/` and has the open pull request. If the current branch is `main`, check
   that branch out first (`git fetch origin` then `git checkout <branch>`). If the pull request is
   already merged, create a branch named `<name>-archive` from `main` instead.
2. After the archive completes (the folder moved under `openspec/changes/archive/`, the main specs
   synced), commit everything it touched with a conventional message
   (`docs(openspec): archive <name>`) and push the branch: `git push -u origin <branch>`. The push
   runs the repo's pre-push gate; a gate failure is fixed before pushing again.
3. If a new branch was needed, open a small pull request from it to `main`, titled after the
   archive, with the GitHub tools when the session has them and `gh pr create` otherwise.

**Amendment 2 — step 4 syncs without asking.** This command is reached only after the person has
tested the built change, so the delta specs describe what shipped. Archiving without syncing would
leave the main specs describing the app as it was, and the next `/DefineFeature` reads them as
truth; the person running this cannot judge that choice. So step 4 asks NOTHING:

- Changes needed: show the combined summary, then route as if "Sync now" were chosen — the specs
  instructions lookup, the inline sync, and the re-comparison, stopping without archiving on any
  mismatch.
- Already synced: route as if "Archive now" were chosen.

Stop to ask only when something is actually wrong. The confirmations for incomplete artifacts or
tasks stand. If a main spec has changed since the proposal so that a delta no longer merges cleanly
— a MODIFIED, REMOVED or RENAMED requirement it targets is gone — stop and explain the mismatch in
plain words rather than guessing a merge.

**Amendment 3 — the ending.** Replace the success output's closing with exactly this, where
`<PR link>` is the pull request the archive commit rides in:

"This change is finished and filed away. Merge its pull request on GitHub when you are ready:
`<PR link>`. Then, for the next one, start a new chat and use `/DefineFeature`."

Merging is the person's click on GitHub, never done from here.

ARGUMENTS: $ARGUMENTS
