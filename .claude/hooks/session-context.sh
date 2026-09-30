#!/usr/bin/env bash
# session-context.sh — SessionStart hook.
#
# Injects the workflow rule at the top of every session. This exists because
# CLAUDE.md content can be lost or diluted after a compaction. Re-injecting
# is cheap insurance.
#
# This is NOT enforcement — boundary-guard.sh is. This just means the model
# knows the rule before it tries something the guard would block, which turns
# a hard denial into a non-event.

set -uo pipefail
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "PROJECT WORKFLOW: OpenSpec is the source of truth in this repo. Planning artifacts live only in openspec/changes/<name>/ - a PreToolUse hook denies plan or design writes anywhere else (docs/plans/, docs/specs/). Artifacts describe the work, not who runs it; never embed an executor directive. /opsx:apply is the only executor. Open an OpenSpec change only when asked to.\n\nGUIDED FLOW PHASE ENDINGS (these override any closing prompt inside the openspec skills): when a proposal is complete and the user has nothing further, end with exactly: 'When you are satisfied with the specification, begin a new chat and use /WriteCode to realize the changes.' A new chat for /WriteCode is mandatory - a hook blocks applying in the chat that proposed; never offer to apply in that chat. More generally, each of /DefineFeature, /WriteCode, /UpdateDocs runs at most once per chat, in that order; a second feature needs a new chat, and the hook refuses a repeat or a step back. Exception: in a cloud session (CLAUDE_CODE_REMOTE=true) a new chat loses the proposal, so end instead with exactly: 'When you are satisfied with the specification, use /WriteCode in this chat to realize the changes.' Every message ending with either /WriteCode sentence first lists, in full and as plain chat text (never inside a question tool), every ASSUMED line from the change's discovery.md, re-read from disk - or says in one line that nothing was assumed. When apply completes, first publish the change as a pull request and wait for the Preview workflow's link (the /WriteCode command says how), then hand off with the preview link and concrete testing steps in product language and end with exactly: 'When you have tested it and everything works the way you expect, use /UpdateDocs to file this change away.' If the user reports successful testing of an applied change, remind them of /UpdateDocs. Archive commits and pushes on the change's branch so the archive rides in its pull request (the /UpdateDocs command says how); when it completes, end with exactly: 'This change is finished and filed away. Merge its pull request on GitHub when you are ready: <PR link>. Then, for the next one, start a new chat and use /DefineFeature.' Merging is the person's click on GitHub, never done from a chat. In a cloud session a finished proposal is committed and pushed on the session's branch without opening a pull request (a push is a save; a pull request is a review). Lost at any point: /Align names the situation and the one next step."
  }
}
JSON
exit 0
