#!/usr/bin/env bash
# boundary-guard.sh — PreToolUse hook.
#
# THIS IS THE ENFORCEMENT MECHANISM. Everything in CLAUDE.md is explanation;
# this file is what actually holds the line: OpenSpec is the source of truth
# for planning artifacts, so plan and design documents are written under
# openspec/changes/ and nowhere else.
#
# Contract: reads the hook event JSON on stdin, always exits 0.
#   deny  -> one JSON line on stdout:
#            {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#             "permissionDecision":"deny","permissionDecisionReason":"..."}}
#   allow -> no output; the normal permission flow decides.
#
# No jq, no python, no network. Pure grep so it costs ~5ms on the tool loop
# and runs on a GUI-launched client's bare PATH (macOS bash 3.2, BSD grep).

set -uo pipefail

# Tools resolve from the pinned toolchain when the `.devshell` out-link
# exists (see AGENTS.md "Agents in a sandboxed client"); otherwise from the
# host, which is why everything below stays bash-3.2/BSD-safe. Locale is
# host state too.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.devshell/bin" ]; then
  PATH="$CLAUDE_PROJECT_DIR/.devshell/bin:$PATH"
fi
export LC_ALL=C

EVENT="$(cat)"
FLAT="$(printf '%s' "$EVENT" | tr -d '\n\r')"

# Cheap field reads. Deliberately tolerant: if we can't parse, we allow.
# A guard that crashes closed would break the session; a guard that misses
# one call is caught later by bin/boundary-check.sh. Fields are extracted
# per-tool below, never globally: a JSON key can only match at the level it
# actually exists (string values keep their quotes escaped), and scoping the
# reads to the dispatching tool keeps it that way.
field() {
  printf '%s' "$FLAT" |
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" |
    head -n1 |
    sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"$//"
}

TOOL="$(field tool_name)"

# Reasons are static single-line strings with literal \n escapes; they must
# pass through %s (a printf FORMAT would turn \n into real newlines and
# break the JSON).
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

FORBIDDEN_PATHS='docs/plans(/|$)|docs/specs(/|$)'

case "$TOOL" in

  # --- Rule 1: planning artifacts live only under openspec/changes/ ----------
  # A plan or design written anywhere else becomes a second source of truth
  # that OpenSpec never syncs or archives.
  Write | Edit | MultiEdit | NotebookEdit | Create | create_file | str_replace)
    PATH_ARG="$(field file_path)"
    if printf '%s' "$PATH_ARG" | grep -qE "$FORBIDDEN_PATHS"; then
      deny "BLOCKED: $PATH_ARG\n\nOpenSpec owns planning artifacts in this project. Writing a plan or design\nhere creates a second source of truth that never gets synced or archived.\n\nWrite instead to:\n  design  -> openspec/changes/<change-name>/design.md\n  plan    -> openspec/changes/<change-name>/tasks.md\n\nIf no change folder exists yet, stop and tell the user to run /propose."
    fi
    ;;

  # --- Rule 2: no planning artifacts via shell redirection -------------------
  Bash)
    CMD_ARG="$(field command)"
    if [ -n "$CMD_ARG" ] && printf '%s' "$CMD_ARG" | grep -qE "(>|>>|tee|cp|mv|mkdir).*($FORBIDDEN_PATHS)"; then
      deny "BLOCKED: shell command writes to a forbidden planning path.\n\nOpenSpec owns planning artifacts. Use openspec/changes/<change-name>/ instead."
    fi
    ;;

esac

exit 0
