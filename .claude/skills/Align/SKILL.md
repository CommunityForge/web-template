---
name: Align
description: Where am I in this project, and what is the one next step
disable-model-invocation: true
---

# /Align

The person is lost: a chat closed, a week passed, a fix loop went nowhere, a second change began while
the first is unmerged. Read the project, name the single **situation** they are in, in product words,
and hand them exactly one **next step**. Free text after the command (`/Align the login page still
looks wrong after three tries`) jumps to the matching row; the probe still runs so the answer is
grounded in the files, not the story.

## Steps

1. **Probe.** Run `bash bin/align-probe.sh` with the Bash tool and read every line; the header of
   that script defines each key and sentinel. Done when every section printed a value or a sentinel.
   When `github.status` is not `ok` and this session has GitHub tools, fill the `pr.*` facts in the
   same shape from them: open pull requests into `main`, each one's checks, the last comment whose
   body starts `## Preview`, and whether the branch's tree holds the change under
   `openspec/changes/archive/`. Without GitHub tools either, the branch scan stands in and the
   handoff carries the sentence "I couldn't check your open reviews". Done when the PR facts exist
   or that sentence is queued.
   When `repo.docs_context_unindexed` is above 0, file the stragglers before anything else: open
   each file under `docs/context/` whose path the `README.md` does not mention, and append its
   index line (what it is, when to open it), recreating the README first if it is missing, per
   `references/context-docs.md`. This is bookkeeping, NOT a situation: no question, no mention to
   the person, and it waits to be committed with the next change. Done when every file has a line.
2. **Situation.** Walk the priority list; the first matching row is the situation, exactly one. Set
   aside at most two "also worth knowing" facts for the end of the handoff. Done when one row is
   chosen.
3. **Split, if the files can't tell.** Ask at most one question, one per message, in the Guided
   shape (plain words, parallel neutral options): tested or not, bug or drift, which change. Done
   when the answer lands the person on one row.
4. **Handoff.** The Guided handoff shape: what is true, what it means for them, the one next step
   with the exact command and which chat to type it in (this one or a new one), and the fixed
   phase-ending sentence verbatim where the row names one. Done when the message ends on the command.
5. **Act on a clear yes.** Beyond step 1's index bookkeeping, only the local, reversible actions
   the row names: commit, create or
   check out a branch, push a branch, delete an abandoned change folder. Merging or closing a pull
   request is the person's click on GitHub, always. Done when `git status` shows exactly what was
   offered and nothing else.

## Words

- **situation** (one) and **next step** (one). A handoff with two next steps has not chosen.
- **Stages** of a change, as the probe emits them: `proposing` (folder, no `tasks.md`), `planned`
  (no task checked), `building` (some checked), `built` (all checked, no open pull request),
  `previewing` (open pull request with a preview link, not yet archived on that branch), `filed`
  (archived on the branch, pull request still open), `merged` (`origin/main` has the archive).
- **bug** vs **drift** after building: a bug is "it isn't doing what we agreed"; drift is "it does
  what we agreed and we were wrong".
- **stale**: an older open review while newer work by the same person exists. Finish the older one
  first.
- **NEEDS YOU**: the Guided register for anything only the person, or whoever owns the accounts, can
  do. Plain words, no softening.
- **save**: in a cloud session, pushing the branch IS saving; the chat is temporary and its
  checkout goes with it. A push is free and opens nothing. A pull request is a review, never a save.
- Phrase every next step positively: "the next step is", never a "don't".

## Two places the truth can live

| Fact                            | Local (desktop app)                                                       | Cloud (`session.kind=cloud`)                                                                                                                                 |
| ------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Where a change's files are      | The working tree, durably (`change.N.*`), plus whatever was pushed        | Only branches on `origin` (`branch.N.*`) and pull requests. The working tree is a fresh `claude/…` branch; an unpushed proposal from an earlier chat is gone |
| "New chat, `/WriteCode <name>`" | Exactly that; a hook enforces the fresh chat                              | On a yes: `git fetch origin && git checkout <branch>` here, then "use `/WriteCode <name>` in this chat"                                                      |
| Making work durable             | Commit; pushing is sharing                                                | Commit and push the branch; no pull request                                                                                                                  |
| Setup                           | `Setup.command` / `Setup.ps1`; the probe reads its todo list (`wizard.*`) | `session-bootstrap.sh`, which names its own retry command in the session context; no wizard                                                                  |

Two wizard todo lines are noise, present on every non-interactive run: `nix develop -c pnpm check`
(that stage always skips without a terminal) and the GitHub line while `main` has no upstream.

## Priority

1. Work at risk
2. Broken
3. In flight (one change at a time)
4. Setup gaps
5. Nothing in flight

The focused change: with one change in `change.N` or `branch.N` it is that one; with several, the
_Several_ row picks it before any stage row runs. Every stage row accepts its fact from either
`change.N.*` (working tree) or `branch.N.*` (branch only).

### A. Work at risk

| Row                   | Detect                                                                                    | Next                                                                                                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unsaved               | any `git.dirty.*` > 0                                                                     | "This work exists only here." Offer to save it: commit on the change's branch; in cloud, also push. On `main`, the _On main_ row runs first.                                           |
| On main               | `git.on_main=yes` and (`git.ahead_of_origin_main` > 0 or `git.dirty.code` > 0)            | It needs its own lane before it can get a preview. Offer to move it to a branch named after the change, commit, push.                                                                  |
| Not pushed            | `git.upstream=none` or `git.ahead` > 0, with commits or a change on this branch           | Cloud: the top risk; this chat is the only copy. Offer to save it to GitHub (commit, push the branch, no pull request). Local: same offer, lower urgency, phrased as "not yet shared". |
| Lost plan (cloud)     | free text names a change no `change.N`, `branch.N` or `pr.N` carries                      | Say plainly that a plan written in an earlier chat and never saved is gone, and that saving is now part of finishing a proposal. Next: `/DefineFeature <idea>` in this chat.           |
| Code without a change | `git.dirty.code` > 0 or code commits ahead of `origin/main`, and no change on this branch | The written record no longer matches the app. Two parallel options, neither recommended: fold it into a change (new chat, `/DefineFeature` describing what was done) or undo it.       |
| Behind GitHub         | `git.behind_origin_main` > 0                                                              | Offer to bring this copy up to date (`git pull --ff-only origin main` on `main`, or merge `origin/main` into the branch) before anything new.                                          |

### B. Broken

| Row                           | Detect                                                                                              | Next                                                                                                                                            |
| ----------------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Review checks red             | `pr.N.checks=fail` and `preview_failed_step` is `other` or `none`                                   | New chat on that branch: "make the review pass". The desktop app's Auto-fix on the pull request also works.                                     |
| Preview needs settings        | `pr.N.preview_failed_step` is `settings` or `supabase`                                              | NEEDS YOU: whoever owns the accounts. Name the missing piece in plain words and point at the README's Deploying section. Not fixable in a chat. |
| Live site didn't update       | `deploy.main=failure`                                                                               | Same NEEDS YOU treatment; the failing step of the Deploy workflow names the setting.                                                            |
| Setup unfinished (local)      | `wizard.todo.*` beyond the two noise lines, `wizard.status=stopped-early`, or `session.devshell=no` | Double-click the setup wizard again; name the stage it will pick up at. Privileged stages (installing Nix, signing in) are never run from here. |
| Environment not ready (cloud) | `session.kind=cloud` and (`session.devshell=no` or no `node_modules/.modules.yaml`)                 | The bootstrap stopped early; its message in this session's context names the retry command. Run it on a yes, then probe again.                  |
| Project not personalized      | `repo.replaceme=yes`                                                                                | One line: ask whoever set the project up to finish it (the README's "Renaming on fork"). Everything else still applies.                         |

### C. In flight

| Row                       | Detect                                                                        | Next                                                                                                                                                                                                                                                                                                                                   |
| ------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Several                   | `change.count` + `branch.count` > 1, or a `pr.N` older than the newest change | List each with its stage and a one-line gist from its `proposal.md`. A stale review: finish the older one first (test → `/UpdateDocs` → merge); each open review also holds its own preview environment, so one at a time is the calm path. Ask which one they are on; route it.                                                       |
| `proposing`               | `stage=proposing`                                                             | The plan wasn't finished. New chat, `/DefineFeature <name>`; it asks "continue or new" for an existing name.                                                                                                                                                                                                                           |
| `planned`                 | `stage=planned`                                                               | Two plain lines from `proposal.md`, then every ASSUMED line from `discovery.md` in full (or one line saying none). Happy: "When you are satisfied with the specification, begin a new chat and use `/WriteCode` to realize the changes." (cloud: "use `/WriteCode` in this chat"). Want it different: new chat, `/opsx:update <name>`. |
| `building`                | `stage=building`                                                              | "Building got N of M steps in." New chat, `/WriteCode <name>` picks up where it stopped.                                                                                                                                                                                                                                               |
| `built`, no pull request  | `stage=built` and no `pr.N.change=<name>`                                     | The preview step didn't finish. New chat, `/WriteCode <name>`: with every task done it publishes the preview.                                                                                                                                                                                                                          |
| `previewing`              | `pr.N.change=<name>`, `preview_url` set, `archived=no`                        | One question: tried it yet? No: the preview link plus what to try first, derived per `references/testing-steps.md`. Yes and happy: "When you have tested it and everything works the way you expect, use `/UpdateDocs` to file this change away." Yes and wrong: section D.                                                            |
| `filed`                   | `pr.N.archived=yes` or `branch.N.archived=yes`, pull request open             | NEEDS YOU, plainly: "Filed away and waiting for your merge." The pull request link; merging is their click on GitHub.                                                                                                                                                                                                                  |
| Merged, never filed       | `change.N.branches` includes `origin/main`                                    | "Live but not filed, so the written description is out of date." `/UpdateDocs <name>` in this chat; it opens a small pull request for the archive.                                                                                                                                                                                     |
| Feature step in this chat | this chat's own transcript (no probe key)                                     | One sentence on why each step needs a fresh chat, then: new chat, and the next command for the stage the probe reports. Cloud, right after `/DefineFeature`: `/WriteCode` in this chat.                                                                                                                                                |
| Drop or restart           | free text                                                                     | Say what is lost. On a clear yes: delete the change folder and its local branch if unmerged; closing the pull request is their click. Then new chat, `/DefineFeature`.                                                                                                                                                                 |

### D. Stuck after building

One question splits **bug** from **drift**. Each playbook is reached only from its row.

| Row     | Next                                                                                                                                                                                                                                                                            |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bug     | Coach the report per `references/bug-report.md`: did, expected, saw, screenshot. One bug per fresh chat, on the change's branch, inside this change.                                                                                                                            |
| Drift   | Not merged: new chat, `/opsx:update <name>`, then new chat, `/WriteCode <name>`. Merged or filed: a new change, new chat, `/DefineFeature`.                                                                                                                                     |
| Thrash  | Many rounds, fixes undoing fixes (free text, or many fix-type commits since the last task was checked). Say plainly that long chats get worse at this. Draft the restatement per `references/restart.md` for a fresh chat. The same thing back three times: re-propose smaller. |
| Too big | Finish what works, `/UpdateDocs`, propose the rest as its own change.                                                                                                                                                                                                           |

### E. Setup gaps

| Row               | Detect                                | Next                                                                                                                                                                                                      |
| ----------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No context docs   | `repo.docs_context` is `missing` or 0 | Why it matters (fewer, better questions during `/DefineFeature`), what belongs there per `references/context-docs.md`, and the offer to save attached files into `docs/context/` with an index line each. |
| Thin context docs | a small count, old commit dates       | An "also worth knowing" line at most.                                                                                                                                                                     |

### F. Nothing in flight

| Row               | Next                                                                                                                                                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nothing yet       | A plain summary of `openspec/specs/`, the cycle in three lines (`/DefineFeature` → new chat `/WriteCode` → test → `/UpdateDocs` → merge), help pick a small first win. New chat, `/DefineFeature <idea>`. Context docs first if missing. |
| Between changes   | Confirm the good place, summarize what the app does today. New chat, `/DefineFeature`.                                                                                                                                                   |
| Just a question   | Answer from the specs or the workflow. No state lecture.                                                                                                                                                                                 |
| Exploring an idea | `/opsx:explore`, which writes nothing.                                                                                                                                                                                                   |
