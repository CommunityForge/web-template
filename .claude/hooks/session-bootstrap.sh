#!/usr/bin/env bash
# session-bootstrap.sh — SessionStart hook.
#
# Makes a cloud session (Claude Code on the web) ready to run the repo's checks
# before its first prompt: the pinned toolchain at `.devshell/bin`, the
# workspace's dependencies, the git hooks, and the toolchain on PATH for the
# rest of the session. Any other client exits at the gate below: on a desktop
# the dev shell is the human's to enter, and `.devshell` is opt-in.
#
# The cloud container carries Nix and nothing else of ours. Without this hook
# the first `pnpm check` fails and the agent spends its opening turns
# rediscovering `nix build .#toolchain`. The container's state is cached once
# the hook completes, so the cold path (about a minute, all of it fetches) is
# paid once per environment and the warm path is a few seconds of evaluation.
#
# `.devshell` is the PATH entry; the dev shell is entered once, for its
# shellHook, which is what installs the commit-time and push-time git hooks.
#
# Contract: exit 0 ALWAYS. A stage that fails is reported on stdout, which
# reaches the agent as session context, so it knows what is missing and the
# command that retries it. A hook that failed the session would leave the
# person with nothing, which is worse than a session that has to bootstrap.

set -uo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0

LOG="${TMPDIR:-/tmp}/session-bootstrap.log"
: >"$LOG"

# stage <name> <command...>: runs the command with its output in $LOG. On
# failure, prints one line for the agent and stops the chain -- every stage
# below depends on the one before it.
stage() {
  local name="$1"
  shift
  if "$@" >>"$LOG" 2>&1; then
    return 0
  fi
  printf 'session-bootstrap: %s did not complete; the rest of the toolchain setup was skipped. Retry with: %s. Output is in %s.\n' \
    "$name" "$*" "$LOG"
  exit 0
}

stage "toolchain build" nix build .#toolchain --out-link .devshell
export PATH="$PWD/.devshell/bin:$PATH"
stage "dependency install" pnpm install
# The shellHook installs the git hooks (`nix fmt` at commit, the cheap check
# gate at push) and refreshes the tracked `.pre-commit-config.yaml` link.
stage "git hooks install" nix develop -c true

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  # The `$PATH` is meant to be literal: it is expanded when the session sources the file.
  # shellcheck disable=SC2016
  printf 'export PATH="%s/.devshell/bin:$PATH"\n' "$PWD" >>"$CLAUDE_ENV_FILE"
fi

exit 0
