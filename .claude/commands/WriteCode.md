---
description: Write the code for a feature
---

Follow the instructions in @.claude/commands/opsx/apply.md exactly, with two amendments.

**Amendment 1 — publish a preview before completing.** A change is not complete when its last
task is checked off; it is complete when the person has a link they can click. Once every task
is done and the repo's checks pass (`pnpm check`, `pnpm lint`, `pnpm test`, `pnpm test:types`),
do this before writing the completion output:

1. Never commit to or push `main`. If the current branch is `main`, create a branch named after
   the change (`<change-name>`) and stay on it. In a cloud session the branch already exists;
   keep it.
2. Commit everything the change touched with a conventional message, and push the branch:
   `git push -u origin <branch>`. The push runs the repo's pre-push gate (formatting, spelling,
   workflow lint); a gate failure is part of the change and is fixed before pushing again.
3. Open a pull request from the branch to `main`, titled after the change, with the GitHub tools
   when the session has them and `gh pr create` otherwise. If the branch already has an open
   pull request, reuse it. The pull request is the only thing that produces a preview — nothing
   is published from a laptop or a session.
4. Wait for the preview link. The `Preview` workflow comments on the pull request with a body
   beginning `## Preview 🔶` and the URL, normally within five minutes of the push. Poll the
   pull request's comments until it appears, up to fifteen minutes. If the workflow fails, read
   the failing step: a failure inside the change's own code is yours to fix and push; a missing
   repository setting or an account step is the person's to do, and the workflow's message names
   it — say so plainly instead of retrying.
5. If the branch has no commits beyond `main`, there is nothing to preview; say that in the
   handoff instead of opening an empty pull request.

**Amendment 2 — the completion output.** Replace the **Output On Completion** block (the
change/schema/progress header and the per-task checklist; the checklist already lives on disk
in `tasks.md`) with a plain-language testing handoff:

- "Ready for you to test." plus one line on what is different now, in terms of what the person
  can do or see.
- The preview link on its own line, followed by the pull request link. The preview is where
  they test; the pull request is where the change is reviewed and merged, and merging is what
  publishes it for real.
- What to try first, concretely — name the actual screen, button, or action, drawn from the
  change's own spec and tasks. Never say "run the tests".
- End with exactly this sentence and nothing after it:

  "When you have tested it and everything works the way you expect, use `/UpdateDocs` to file
  this change away."

The **Output On Pause (Issue Encountered)** behavior is unchanged.

ARGUMENTS: $ARGUMENTS
