#!/usr/bin/env bash
# fresh-session-guard.sh — PreToolUse + UserPromptSubmit hook.
#
# THIS IS THE ENFORCEMENT MECHANISM for the guided flow's phase boundary:
# /apply must run in a fresh chat. A session whose transcript shows a propose
# invocation may not also apply — everything apply needs is on disk, and a
# large planning transcript is the main cause of slow, degraded apply runs.
#
# Two entry points, because the two clients differ:
#   PreToolUse (Skill|SlashCommand) — the model invoking apply as a tool.
#   UserPromptSubmit               — the person typing /apply in a terminal
#                                    client, where commands never reach
#                                    PreToolUse.
#
# Contract: reads the hook event JSON on stdin, always exits 0.
#   deny (PreToolUse)        -> {"hookSpecificOutput":{"hookEventName":
#                                "PreToolUse","permissionDecision":"deny",...}}
#   block (UserPromptSubmit) -> {"decision":"block","reason":"..."}
#   allow                    -> no output.
#
# No jq, no python, no network. Pure grep so it costs ~5ms on the tool loop
# and runs on a GUI-launched client's bare PATH (macOS bash 3.2, BSD grep).
# Anything unparsable, including a missing or unreadable transcript, allows:
# a guard that crashes closed would break the session.

set -uo pipefail

# A cloud session (CLAUDE_CODE_REMOTE=true) is sandboxed: a new chat starts
# from a fresh checkout and the proposal written here is gone, so the guard
# would make /apply impossible rather than faster. Allow it there.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0

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

# A propose run leaves one of these in the transcript, and nothing else does:
# a typed /propose (command-name tag), a Skill invocation of a propose skill
# (plain or string-escaped JSON), or a SlashCommand invocation of /propose.
# Prose that merely mentions /propose — like the session-context rule text —
# matches none of them.
PROPOSE_EVIDENCE='<command-name>/?(opsx:)?propose</command-name>|"skill"[[:space:]]*:[[:space:]]*"((opsx:)?propose|openspec-propose)"|\\"skill\\":[[:space:]]*\\"((opsx:)?propose|openspec-propose)\\"|"command"[[:space:]]*:[[:space:]]*"/(opsx:)?propose'

proposed_in_this_session() {
  TRANSCRIPT="$(field transcript_path)"
  [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] &&
    grep -qE "$PROPOSE_EVIDENCE" "$TRANSCRIPT"
}

REASON='BLOCKED: /apply cannot run in the chat where the proposal was written.\n\nTell the person: planning happened in this chat, so applying here is not possible. Begin a new chat and use /apply there - a fresh chat is required and makes the work faster and more reliable.'

case "$(field hook_event_name)" in

  PreToolUse)
    case "$(field tool_name)" in
      Skill | SlashCommand)
        NAME="$(field skill)"
        [ -n "$NAME" ] || NAME="$(field command)"
        if printf '%s' "$NAME" | grep -qE '^/?(opsx:)?apply([[:space:]]|$)|^openspec-apply-change$'; then
          if proposed_in_this_session; then
            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
            exit 0
          fi
        fi
        ;;
    esac
    ;;

  UserPromptSubmit)
    PROMPT="$(field prompt)"
    if printf '%s' "$PROMPT" | grep -qE '^[[:space:]]*/(opsx:)?apply([[:space:]]|$)'; then
      if proposed_in_this_session; then
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
      fi
    fi
    ;;

esac

exit 0
