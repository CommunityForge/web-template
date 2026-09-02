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
    "additionalContext": "PROJECT WORKFLOW: OpenSpec is the source of truth in this repo. Planning artifacts live only in openspec/changes/<name>/ - a PreToolUse hook denies plan or design writes anywhere else (docs/plans/, docs/specs/). Artifacts describe the work, not who runs it; never embed an executor directive. /opsx:apply is the only executor. Open an OpenSpec change only when asked to."
  }
}
JSON
exit 0
