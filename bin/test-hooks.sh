#!/usr/bin/env bash
# test-hooks.sh — prove the guard denies what it should and allows what it should.
#
# This is the piece that makes the boundary a tested mechanism rather than a
# hopeful one. It feeds real PreToolUse event payloads to boundary-guard.sh and
# asserts the exit code. Run it after install, and after any Superpowers or
# Claude Code upgrade.

set -uo pipefail

GUARD="${1:-.claude/hooks/boundary-guard.sh}"
[ -x "$GUARD" ] || {
  echo "Not executable: $GUARD"
  exit 1
}

PASS=0
FAIL=0

# expect: "deny" or "allow"
check() {
  local name="$1" expect="$2" payload="$3"
  local rc
  printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1
  rc=$?
  local got="allow"
  [ "$rc" -eq 2 ] && got="deny"
  if [ "$got" = "$expect" ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (expected %s, got %s, rc=%s)\n' \
      "$name" "$expect" "$got" "$rc"
    FAIL=$((FAIL + 1))
  fi
}

echo
echo "Boundary guard tests"
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

check "dispatch subagent-driven-development" deny \
  '{"tool_name":"Task","tool_input":{"description":"implement tasks","prompt":"Use superpowers:subagent-driven-development to work through the plan","subagent_type":"general-purpose"}}'

check "invoke executing-plans" deny \
  '{"tool_name":"Skill","tool_input":{"name":"superpowers:executing-plans"}}'

check "invoke writing-plans" deny \
  '{"tool_name":"Skill","tool_input":{"name":"superpowers:writing-plans"}}'

check "REQUIRED SUB-SKILL leaking into tasks.md" deny \
  '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/tasks.md","content":"> REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development"}}'

# --- must ALLOW -------------------------------------------------------------

check "normal source edit" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"src/todo/page.tsx","content":"export default function Page(){}"}}'

check "OpenSpec artifact write" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/tasks.md","content":"- [ ] Add the route"}}'

check "OpenSpec delta spec" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"openspec/changes/add-todo/specs/todo/spec.md","content":"Requirement: SHALL persist"}}'

check "brainstorming skill is permitted" allow \
  '{"tool_name":"Skill","tool_input":{"name":"superpowers:brainstorming"}}'

check "systematic-debugging is permitted" allow \
  '{"tool_name":"Skill","tool_input":{"name":"superpowers:systematic-debugging"}}'

check "code review subagent is permitted" allow \
  '{"tool_name":"Task","tool_input":{"description":"review the diff","prompt":"Review this change for correctness","subagent_type":"general-purpose"}}'

check "ordinary bash" allow \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

check "payload is not parseable and fails open" allow \
  'not json at all'

check "doc mentioning the word plans" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"docs/architecture/plans-overview.md","content":"notes"}}'

# Regression: writing ABOUT the banned skills must not be blocked. This kit's
# own README names them, as would any ADR explaining the boundary.
check "doc naming subagent-driven-development in prose" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"We do not use subagent-driven-development here."}}'

check "ADR explaining why executing-plans is disabled" allow \
  '{"tool_name":"Write","tool_input":{"file_path":"docs/adr/0004-boundary.md","content":"executing-plans is disabled because it competes with /opsx:apply."}}'

check "CLAUDE.md listing banned skills" allow \
  '{"tool_name":"Edit","tool_input":{"file_path":"CLAUDE.md","old_string":"x","new_string":"Never invoke writing-plans or executing-plans."}}'

echo
echo "  $PASS passed, $FAIL failed"
echo
[ "$FAIL" -eq 0 ] || exit 1
