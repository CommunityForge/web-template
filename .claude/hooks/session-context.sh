#!/usr/bin/env bash
# session-context.sh — SessionStart hook.
#
# Injects the boundary rules at the top of every session. This exists because
# CLAUDE.md content can be lost or diluted after a compaction, and Superpowers
# has a known post-compaction bootstrap loss. Re-injecting is cheap insurance.
#
# This is NOT enforcement — boundary-guard.sh is. This just means the model
# knows the rule before it tries something the guard would block, which turns
# a hard denial into a non-event.

set -uo pipefail
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "PROJECT WORKFLOW BOUNDARY: OpenSpec owns the workflow in this repo. Superpowers skills are available individually (brainstorming, test-driven-development, systematic-debugging, requesting-code-review) but must not be chained. Do not invoke writing-plans, executing-plans, or subagent-driven-development; a PreToolUse hook blocks them. Planning artifacts live only in openspec/changes/<name>/ - never docs/superpowers/. After the brainstorming skill's spec-review gate, stop and hand off to /opsx:continue rather than proceeding to its final step. /opsx:apply is the only executor."
  }
}
JSON
exit 0
