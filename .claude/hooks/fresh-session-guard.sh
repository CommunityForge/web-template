#!/usr/bin/env bash
# fresh-session-guard.sh — PreToolUse + UserPromptSubmit hook.
#
# THIS IS THE ENFORCEMENT MECHANISM for the guided flow's phase boundaries:
# a chat carries AT MOST ONE pass through the cycle. The cycle's stages, each
# with every name that enters it:
#
#   1 define  DefineFeature  opsx:propose  openspec-propose
#   2 write   WriteCode      opsx:apply    openspec-apply-change
#   3 docs    UpdateDocs     opsx:archive  openspec-archive-change
#
# Entering stage N is refused when the transcript already shows an invocation
# of any stage >= N — a repeat, or a step backwards. Everything a later stage
# needs is on disk, and a large transcript from an earlier pass is the main
# cause of slow, degraded runs.
#
# Two refinements:
#   - Locally, stage 2 is ALSO refused after stage 1: /WriteCode runs in a
#     fresh chat. A cloud session (CLAUDE_CODE_REMOTE=true) is exempt from
#     this one rule only, because a new chat there starts from a fresh
#     checkout and the proposal written in this chat would be gone.
#   - The openspec-* names are skills only the model invokes, from inside the
#     alias command that entered the same stage. For them a SAME-stage match
#     does not refuse; only a later stage does.
#
# Two entry points, because the two clients differ:
#   PreToolUse (Skill|SlashCommand) — the model invoking a stage as a tool.
#                                    Its own tool_use line may already be in
#                                    the transcript, so lines carrying the
#                                    payload's tool_use_id are dropped before
#                                    matching; with no id, the same-stage
#                                    check is skipped rather than self-block.
#   UserPromptSubmit               — the person typing a command. It fires
#                                    before the expanded command line is
#                                    written, so nothing needs dropping.
#
# Contract: reads the hook event JSON on stdin, always exits 0.
#   deny (PreToolUse)        -> {"hookSpecificOutput":{"hookEventName":
#                                "PreToolUse","permissionDecision":"deny",...}}
#   block (UserPromptSubmit) -> {"decision":"block","reason":"..."}
#   allow                    -> no output.
#
# The two reasons have different readers. A PreToolUse reason goes to the
# model, which relays it. A UserPromptSubmit reason is shown to the PERSON
# VERBATIM and never reaches the model, so it is written for someone who
# cannot read code: it names the step this chat already ran and the command
# to type in a new chat, and nothing else.
#
# No jq, no python, no network. Pure grep so it costs ~5ms on the tool loop
# and runs on a GUI-launched client's bare PATH (macOS bash 3.2, BSD grep).
# Anything unparsable, including a missing or unreadable transcript, allows:
# a guard that crashes closed would break the session.

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

stage_of() {
  case "$1" in
    DefineFeature | opsx:propose | openspec-propose) echo 1 ;;
    WriteCode | opsx:apply | openspec-apply-change) echo 2 ;;
    UpdateDocs | opsx:archive | openspec-archive-change) echo 3 ;;
    *) echo 0 ;;
  esac
}

alias_of() {
  case "$1" in
    1) echo DefineFeature ;;
    2) echo WriteCode ;;
    3) echo UpdateDocs ;;
  esac
}

# Names that can be typed or sent through SlashCommand, and names that can
# reach the Skill tool, for every stage from $1 up to 3.
commands_from() {
  case "$1" in
    1) echo 'DefineFeature|opsx:propose|WriteCode|opsx:apply|UpdateDocs|opsx:archive' ;;
    2) echo 'WriteCode|opsx:apply|UpdateDocs|opsx:archive' ;;
    3) echo 'UpdateDocs|opsx:archive' ;;
  esac
}
skills_from() {
  case "$1" in
    1) echo "$(commands_from 1)|openspec-propose|openspec-apply-change|openspec-archive-change" ;;
    2) echo "$(commands_from 2)|openspec-apply-change|openspec-archive-change" ;;
    3) echo "$(commands_from 3)|openspec-archive-change" ;;
  esac
}

# An invocation leaves one of these in the transcript, and nothing else does:
# a typed command (command-name tag), a Skill invocation (plain or
# string-escaped JSON), or a SlashCommand invocation. Prose that merely
# mentions a command — like the session-context rule text — matches none.
evidence_from() {
  local c s
  c="$(commands_from "$1")"
  s="$(skills_from "$1")"
  printf '%s' '<command-name>/?('"$c"')</command-name>|"skill"[[:space:]]*:[[:space:]]*"('"$s"')"|\\"skill\\":[[:space:]]*\\"('"$s"')\\"|"command"[[:space:]]*:[[:space:]]*"/('"$c"')'
}

TRANSCRIPT="$(field transcript_path)"
SELF_ID=""

# True when the transcript, minus the current call's own lines, shows an
# invocation of any stage from $1 up. Output goes to /dev/null rather than
# grep -q so the reader is never cut off mid-pipe under pipefail.
seen_from() {
  [ "$1" -le 3 ] || return 1
  [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || return 1
  if [ -n "$SELF_ID" ]; then
    grep -vF "$SELF_ID" "$TRANSCRIPT" | grep -E "$(evidence_from "$1")" >/dev/null
  else
    grep -E "$(evidence_from "$1")" "$TRANSCRIPT" >/dev/null
  fi
}

highest_seen_from() {
  local s=3
  while [ "$s" -ge "$1" ]; do
    if seen_from "$s"; then
      echo "$s"
      return
    fi
    s=$((s - 1))
  done
}

# Prints the earlier stage that refuses entering stage $1, or nothing.
# $2 is "exempt" when a same-stage match must not refuse.
refusing_stage() {
  local stage="$1" floor="$1" seen
  [ "$stage" -ge 1 ] || return 0
  [ "${2:-}" = "exempt" ] && floor=$((stage + 1))
  [ "$floor" -le 3 ] && seen="$(highest_seen_from "$floor")"
  if [ -n "${seen:-}" ]; then
    echo "$seen"
  elif [ "$stage" -eq 2 ] && [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] &&
    seen_from 1 && ! seen_from 2; then
    echo 1
  fi
}

# $1 = the stage this chat already ran, $2 = the command to type instead.
person_reason() {
  printf 'This chat has already been used for /%s. Start a new chat and type /%s there. A fresh chat for each step keeps the work fast and reliable.' "$(alias_of "$1")" "$2"
}
model_reason() {
  printf 'BLOCKED: this chat has already run /%s, so /%s cannot run here.\\n\\nTell the person, in plain words, to start a new chat and type /%s there; a fresh chat for each step keeps the work fast and reliable.' "$(alias_of "$1")" "$2" "$2"
}

case "$(field hook_event_name)" in

  PreToolUse)
    case "$(field tool_name)" in
      Skill | SlashCommand)
        NAME="$(field skill)"
        [ -n "$NAME" ] || NAME="$(field command)"
        NAME="$(printf '%s' "$NAME" | sed -E 's/^\///; s/[[:space:]].*$//')"
        SELF_ID="$(field tool_use_id)"
        EXEMPT=""
        case "$NAME" in openspec-*) EXEMPT=exempt ;; esac
        [ -n "$SELF_ID" ] || EXEMPT=exempt
        STAGE="$(stage_of "$NAME")"
        SEEN="$(refusing_stage "$STAGE" "$EXEMPT")"
        if [ -n "$SEEN" ]; then
          case "$NAME" in openspec-*) NAME="$(alias_of "$STAGE")" ;; esac
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(model_reason "$SEEN" "$NAME")"
        fi
        ;;
    esac
    ;;

  UserPromptSubmit)
    PROMPT="$(field prompt)"
    if printf '%s' "$PROMPT" | grep -qE '^[[:space:]]*/(DefineFeature|WriteCode|UpdateDocs|opsx:(propose|apply|archive))([[:space:]]|$)'; then
      NAME="$(printf '%s' "$PROMPT" | sed -E 's/^[[:space:]]*\///; s/[[:space:]].*$//')"
      SEEN="$(refusing_stage "$(stage_of "$NAME")")"
      if [ -n "$SEEN" ]; then
        printf '{"decision":"block","reason":"%s"}\n' "$(person_reason "$SEEN" "$NAME")"
      fi
    fi
    ;;

esac

exit 0
