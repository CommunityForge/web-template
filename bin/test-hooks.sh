#!/usr/bin/env bash
# test-hooks.sh — prove the guard denies what it should and allows what it should.
#
# This is the piece that makes the boundary a tested mechanism rather than a
# hopeful one. It feeds real PreToolUse event payloads to boundary-guard.sh
# and asserts the permission decision. Run it after install, and after any
# Superpowers or Claude Code upgrade.
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

PASS=0
FAIL=0

# expect: "deny" or "allow". Deny is exit 0 plus a permissionDecision JSON
# line on stdout; allow is exit 0 and silence. Exit 2 is the retired legacy
# contract and always fails, as does any stray output on an allow.
check() {
  local name="$1" expect="$2" payload="$3"
  local out rc got
  out="$(printf '%s' "$payload" | "$GUARD" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    got="legacy-deny"
  elif [ "$rc" -ne 0 ]; then
    got="error"
  elif printf '%s' "$out" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
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

  check "write to docs/superpowers/plans" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/plans/2026-08-13-todo.md","content":"# Plan"}}'

  check "write to docs/superpowers/specs" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/2026-08-13-todo-design.md","content":"# Design"}}'

  check "legacy docs/plans dated path" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/2026-08-13-todo.md","content":"# Plan"}}'

  check "edit an existing stray plan" deny \
    '{"tool_name":"Edit","tool_input":{"file_path":"docs/superpowers/plans/x.md","old_string":"a","new_string":"b"}}'

  check "shell redirect into forbidden path" deny \
    '{"tool_name":"Bash","tool_input":{"command":"echo hi > docs/superpowers/plans/x.md"}}'

  check "mkdir of forbidden path" deny \
    '{"tool_name":"Bash","tool_input":{"command":"mkdir -p docs/superpowers/plans"}}'

  check "invoke executing-plans by skill_name" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"superpowers:executing-plans"}}'

  check "invoke executing-plans bare" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"executing-plans"}}'

  check "invoke writing-plans by skill_name" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"superpowers:writing-plans"}}'

  check "invoke writing-plans bare" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"writing-plans"}}'

  check "invoke subagent-driven-development by skill_name" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"superpowers:subagent-driven-development"}}'

  check "invoke subagent-driven-development bare" deny \
    '{"tool_name":"Skill","tool_input":{"skill_name":"subagent-driven-development"}}'

  check "invoke via alternate skill key" deny \
    '{"tool_name":"Skill","tool_input":{"skill":"superpowers:executing-plans"}}'

  check "invoke via legacy name key" deny \
    '{"tool_name":"Skill","tool_input":{"name":"superpowers:executing-plans"}}'

  check "slash command invocation" deny \
    '{"tool_name":"SlashCommand","tool_input":{"command":"/superpowers:writing-plans"}}'

  check "slash command with arguments" deny \
    '{"tool_name":"SlashCommand","tool_input":{"command":"/executing-plans some args"}}'

  check "REQUIRED SUB-SKILL leaking into tasks.md" deny \
    '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/tasks.md","content":"> REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development"}}'

  # --- must ALLOW -------------------------------------------------------------

  check "normal source edit" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"src/todo/page.tsx","content":"export function Page(){}"}}'

  check "OpenSpec artifact write" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/tasks.md","content":"- [ ] Add the route"}}'

  check "OpenSpec delta spec" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/specs/todo/spec.md","content":"Requirement: SHALL persist"}}'

  check "brainstorming skill is permitted" allow \
    '{"tool_name":"Skill","tool_input":{"skill_name":"superpowers:brainstorming"}}'

  check "systematic-debugging is permitted" allow \
    '{"tool_name":"Skill","tool_input":{"skill_name":"superpowers:systematic-debugging"}}'

  check "code review subagent is permitted" allow \
    '{"tool_name":"Task","tool_input":{"description":"review the diff","prompt":"Review this change for correctness","subagent_type":"general-purpose"}}'

  check "ordinary bash" allow \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

  check "payload is not parseable and fails open" allow \
    'not json at all'

  check "doc mentioning the word plans" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/architecture/plans-overview.md","content":"notes"}}'

  # Regression: only invocations are blocked. Talking ABOUT the banned skills —
  # in docs, in prose, or in a subagent prompt — must go through.
  check "Task prompt naming a banned skill in prose" allow \
    '{"tool_name":"Task","tool_input":{"description":"implement tasks","prompt":"Use superpowers:subagent-driven-development to work through the plan","subagent_type":"general-purpose"}}'

  check "Agent prompt mentioning a banned skill" allow \
    '{"tool_name":"Agent","tool_input":{"prompt":"Explain why executing-plans is banned here"}}'

  check "doc naming subagent-driven-development in prose" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"We do not use subagent-driven-development here."}}'

  check "ADR explaining why executing-plans is disabled" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"docs/adr/0004-boundary.md","content":"executing-plans is disabled because it competes with /opsx:apply."}}'

  check "CLAUDE.md listing banned skills" allow \
    '{"tool_name":"Edit","tool_input":{"file_path":"CLAUDE.md","old_string":"x","new_string":"Never invoke writing-plans or executing-plans."}}'

  # Regression: banned slugs match whole names only, not substrings.
  check "skill name containing a banned slug" allow \
    '{"tool_name":"Skill","tool_input":{"skill_name":"my-writing-plans-notes"}}'

  check "skill name extending a banned slug" allow \
    '{"tool_name":"Skill","tool_input":{"skill_name":"writing-plans-v2"}}'

  check "unrelated slash command" allow \
    '{"tool_name":"SlashCommand","tool_input":{"command":"/opsx:apply some change"}}'

  # Regression: field reads are scoped to the dispatching tool — command-shaped
  # text inside a Write's content must not trip the Bash rule.
  check "Write content embedding a command string" allow \
    '{"tool_name":"Write","tool_input":{"file_path":"bin/test-hooks.sh","content":"check deny with \"command\":\"echo hi > docs/superpowers/plans/x.md\" inside"}}'

  # --- deny envelope ----------------------------------------------------------

  local env_out
  env_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/plans/x.md","content":"# Plan"}}' | "$GUARD" 2>/dev/null)"
  if printf '%s' "$env_out" | grep -q '"hookSpecificOutput"' &&
    printf '%s' "$env_out" | grep -q '"hookEventName":"PreToolUse"'; then
    printf '  \033[32mPASS\033[0m  %s\n' "deny envelope carries the PreToolUse contract"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s\n' "deny envelope carries the PreToolUse contract"
    FAIL=$((FAIL + 1))
  fi
}

run_suite "host PATH"

if [ -d "$PWD/.devshell/bin" ]; then
  export CLAUDE_PROJECT_DIR="$PWD"
  run_suite "pinned toolchain via .devshell"
else
  echo
  echo "  (no .devshell out-link; pinned-toolchain pass skipped)"
fi

echo
echo "  $PASS passed, $FAIL failed"
echo
[ "$FAIL" -eq 0 ] || exit 1
