#!/usr/bin/env bash
# block-dangerous-git.sh — PreToolUse hook (Bash matcher).
#
# Blocks destructive git commands before they run. Exit 2 + stderr message
# denies the tool call; exit 0 allows the normal permission flow to decide.

# Tools resolve from the pinned toolchain when the `.devshell` out-link
# exists (see AGENTS.md "Agents in a sandboxed client"); otherwise from the
# host PATH.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.devshell/bin" ]; then
  PATH="$CLAUDE_PROJECT_DIR/.devshell/bin:$PATH"
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

DANGEROUS_PATTERNS=(
  "git reset --hard"
  "git clean -fd"
  "git clean -f"
  "git branch -D"
  "git checkout \."
  "git restore \."
  "reset --hard"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0
