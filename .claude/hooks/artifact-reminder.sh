#!/usr/bin/env bash
# artifact-reminder.sh — PostToolUse hook (Write|Edit|MultiEdit).
#
# The person in the guided flow cannot read a diff, and an in-place edit of a
# proposal renders as nothing BUT a diff. When a person-facing artifact of an
# in-flight change is written — proposal.md or a delta spec.md — this reminds
# the model to hand the file over as a rendered page before the turn ends, so
# the readable version is the last thing on screen.
#
# This is a BACKSTOP, not enforcement: /DefineFeature already asks for the
# hand-over, and this keeps the ask alive through long revision sessions and
# through revisions made outside that command. discovery.md, design.md and
# tasks.md are NOT person-facing and never trigger it; neither does anything
# under openspec/changes/archive/.
#
# Contract: reads the hook event JSON on stdin, always exits 0.
#   person-facing artifact -> {"hookSpecificOutput":{"hookEventName":
#                              "PostToolUse","additionalContext":"..."}}
#   anything else          -> no output.
#
# No jq, no python, no network, for the same reasons as the guards: it runs on
# every write and on a GUI-launched client's bare PATH (macOS bash 3.2, BSD
# grep). Anything unparsable stays silent.

set -uo pipefail

if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.devshell/bin" ]; then
  PATH="$CLAUDE_PROJECT_DIR/.devshell/bin:$PATH"
fi
export LC_ALL=C

EVENT="$(cat)"
FLAT="$(printf '%s' "$EVENT" | tr -d '\n\r')"

field() {
  printf '%s' "$FLAT" |
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" |
    head -n1 |
    sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"$//"
}

case "$(field tool_name)" in
  Write | Edit | MultiEdit) ;;
  *) exit 0 ;;
esac

FILE="$(field file_path)"

printf '%s' "$FILE" |
  grep -qE '(^|/)openspec/changes/[^/]+/(proposal\.md|specs/[^/]+/spec\.md)$' || exit 0
printf '%s' "$FILE" | grep -qE '(^|/)openspec/changes/archive/' && exit 0

MESSAGE="You changed ${FILE}, a document the person reads. The diff you just produced is unreadable to them. Before this turn ends, and before your closing message, send every person-facing file you changed this turn (proposal.md, specs/*/spec.md) to the person as a rendered page with SendUserFile (display: render). If that tool is unavailable, name each changed document in plain words instead of pointing at the diff. Never send discovery.md, design.md or tasks.md."

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MESSAGE"
exit 0
