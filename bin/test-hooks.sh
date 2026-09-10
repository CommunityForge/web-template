#!/usr/bin/env bash
# test-hooks.sh — prove the guard denies what it should and allows what it should.
#
# This is the piece that makes the boundary a tested mechanism rather than a
# hopeful one. It feeds real PreToolUse event payloads to boundary-guard.sh
# and asserts the permission decision. Run it after install, and after any
# Claude Code upgrade.
#
# The suite runs once against the host's tools and, when the `.devshell`
# out-link exists, again with CLAUDE_PROJECT_DIR set so the guard prefers the
# pinned toolchain — the two environments hooks actually execute in.

set -uo pipefail
export LC_ALL=C
unset CLAUDE_PROJECT_DIR

GUARD="${1:-.claude/hooks/boundary-guard.sh}"
[ -x "$GUARD" ] || {
  echo "Not executable: $GUARD"
  exit 1
}
FRESH="${2:-.claude/hooks/fresh-session-guard.sh}"

# Lets check() route through an interpreter when the exec bit is missing.
fresh_guard() { bash "$FRESH"; }

PASS=0
FAIL=0

# expect: "deny" or "allow". Deny is exit 0 plus a permissionDecision JSON
# line (PreToolUse) or a decision:block line (UserPromptSubmit) on stdout;
# allow is exit 0 and silence. Exit 2 is the retired legacy contract and
# always fails, as does any stray output on an allow.
check() {
  local name="$1" expect="$2" payload="$3"
  local out rc got
  out="$(printf '%s' "$payload" | "$GUARD" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    got="legacy-deny"
  elif [ "$rc" -ne 0 ]; then
    got="error"
  elif printf '%s' "$out" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"|"decision"[[:space:]]*:[[:space:]]*"block"'; then
    got="deny"
  elif [ -z "$out" ]; then
    got="allow"
  else
    got="noise"
  fi
  if [ "$got" = "$expect" ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (expected %s, got %s, rc=%s)\n' \
      "$name" "$expect" "$got" "$rc"
    FAIL=$((FAIL + 1))
  fi
}

run_suite() {
  echo
  echo "Boundary guard tests ($1)"
  echo "--------------------"

  # --- must BLOCK -------------------------------------------------------------

  check "write to docs/plans" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/2026-08-13-todo.md","content":"# Plan"}}'

  check "write to docs/specs" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/specs/2026-08-13-todo-design.md","content":"# Design"}}'

  check "edit an existing stray plan" deny \
    '{"tool_name":"Edit","tool_input":{"file_path":"docs/plans/x.md","old_string":"a","new_string":"b"}}'

  check "shell redirect into forbidden path" deny \
    '{"tool_name":"Bash","tool_input":{"command":"echo hi > docs/plans/x.md"}}'

  check "tee into forbidden path" deny \
    '{"tool_name":"Bash","tool_input":{"command":"cat notes.md | tee docs/specs/x.md"}}'

  check "mkdir of forbidden path" deny \
    '{"tool_name":"Bash","tool_input":{"command":"mkdir -p docs/plans"}}'

  # --- must ALLOW -------------------------------------------------------------

  check "normal source edit" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"src/todo/page.tsx","content":"export function Page(){}"}}'

  check "OpenSpec artifact write" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/tasks.md","content":"- [ ] Add the route"}}'

  check "OpenSpec delta spec" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/specs/todo/spec.md","content":"Requirement: SHALL persist"}}'

  check "skill invocation is permitted" allow \
    '{"tool_name":"Skill","tool_input":{"skill_name":"systematic-debugging"}}'

  check "code review subagent is permitted" allow \
    '{"tool_name":"Task","tool_input":{"description":"review the diff","prompt":"Review this change for correctness","subagent_type":"general-purpose"}}'

  check "ordinary bash" allow \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

  check "payload is not parseable and fails open" allow \
    'not json at all'

  check "doc mentioning the word plans" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/architecture/plans-overview.md","content":"notes"}}'

  # Regression: forbidden paths match whole directories only, not filename
  # prefixes beside them.
  check "sibling file named like a forbidden dir" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/plans-overview.md","content":"notes"}}'

  check "doc naming a forbidden path in prose" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"Plans do not live in a docs/plans-style folder here."}}'

  # Regression: field reads are scoped to the dispatching tool — command-shaped
  # text inside a Write's content must not trip the Bash rule.
  check "Write content embedding a command string" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"bin/test-hooks.sh","content":"check deny with \"command\":\"echo hi > docs/plans/x.md\" inside"}}'

  # --- deny envelope ----------------------------------------------------------

  local env_out
  env_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/x.md","content":"# Plan"}}' | "$GUARD" 2>/dev/null)"
  if printf '%s' "$env_out" | grep -q '"hookSpecificOutput"' &&
    printf '%s' "$env_out" | grep -q '"hookEventName":"PreToolUse"'; then
    printf '  \033[32mPASS\033[0m  %s\n' "deny envelope carries the PreToolUse contract"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s\n' "deny envelope carries the PreToolUse contract"
    FAIL=$((FAIL + 1))
  fi
}

run_fresh_suite() {
  echo
  echo "Fresh-session guard tests ($1)"
  echo "-------------------------"

  if [ ! -x "$FRESH" ]; then
    printf '  \033[33mWARN\033[0m  %s lacks its exec bit — Claude Code will not run it (chmod +x). Testing via bash.\n' "$FRESH"
  fi

  local saved_guard="$GUARD"
  GUARD=fresh_guard

  # Fixtures go to the system temp dir, or the repo when that is unwritable
  # (a sandboxed agent's shell allows the cwd but not /var/folders).
  local tdir
  tdir="$(mktemp -d 2>/dev/null)" || tdir="$(mktemp -d .fresh-guard-test.XXXXXX)"

  # Transcripts where a proposal ran, one per way propose can appear.
  printf '%s\n' \
    '{"type":"user","content":"<command-name>/propose</command-name><command-args>add-todo</command-args>"}' \
    >"$tdir/proposed-typed.jsonl"
  printf '%s\n' \
    '{"type":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"opsx:propose"}}]}' \
    >"$tdir/proposed-skill.jsonl"

  # A clean transcript that MENTIONS /propose in prose (the session-context
  # rule text does, every session) — evidence must mean invocation, not mention.
  printf '%s\n' \
    '{"type":"system","content":"When you are ready for the next one, start a new chat and use /propose."}' \
    >"$tdir/clean.jsonl"

  # --- must BLOCK -------------------------------------------------------------

  check "typed /apply after typed /propose" deny \
    "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"prompt\":\"/apply add-todo\"}"

  check "apply skill after typed /propose" deny \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"tool_input\":{\"skill\":\"apply\"}}"

  check "opsx:apply skill after propose skill" deny \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/proposed-skill.jsonl\",\"tool_input\":{\"skill\":\"opsx:apply\"}}"

  check "openspec-apply-change skill after propose skill" deny \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/proposed-skill.jsonl\",\"tool_input\":{\"skill\":\"openspec-apply-change\"}}"

  check "/apply via SlashCommand after propose" deny \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"SlashCommand\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"tool_input\":{\"command\":\"/apply add-todo\"}}"

  # --- must ALLOW -------------------------------------------------------------

  check "apply in a chat that never proposed" allow \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/clean.jsonl\",\"tool_input\":{\"skill\":\"apply\"}}"

  check "typed /apply in a clean chat" allow \
    "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_path\":\"$tdir/clean.jsonl\",\"prompt\":\"/apply\"}"

  check "propose again in the propose chat" allow \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"tool_input\":{\"skill\":\"propose\"}}"

  check "archive after propose" allow \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Skill\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"tool_input\":{\"skill\":\"archive\"}}"

  check "prose mentioning /apply is not a command" allow \
    "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_path\":\"$tdir/proposed-typed.jsonl\",\"prompt\":\"what does /apply do?\"}"

  check "missing transcript fails open" allow \
    '{"hook_event_name":"PreToolUse","tool_name":"Skill","transcript_path":"/nonexistent/t.jsonl","tool_input":{"skill":"apply"}}'

  check "unparsable payload fails open" allow \
    'not json at all'

  rm -rf "$tdir"
  GUARD="$saved_guard"
}

run_suite "host PATH"
run_fresh_suite "host PATH"

if [ -d "$PWD/.devshell/bin" ]; then
  export CLAUDE_PROJECT_DIR="$PWD"
  run_suite "pinned toolchain via .devshell"
  run_fresh_suite "pinned toolchain via .devshell"
else
  echo
  echo "  (no .devshell out-link; pinned-toolchain pass skipped)"
fi

echo
echo "  $PASS passed, $FAIL failed"
echo
[ "$FAIL" -eq 0 ]
