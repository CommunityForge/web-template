#!/usr/bin/env bash
# app-ports.sh — SessionStart hook.
#
# Frees the local app's screen port at the start of a NEW chat (`source`
# startup or clear), so the chat's first `preview_start {name: "app"}` finds
# it free. Resume and compact are left alone, and so is a cloud session
# (CLAUDE_CODE_REMOTE=true), which has no local app.
#
# It is a hook ON PURPOSE: `preview_start` probes the configured port BEFORE it
# runs the launcher, so a port held by a server from an earlier chat or another
# repo is seen as taken before the launcher can take it back, and the model's
# Bash sandbox can stop no process. Hooks run as the client, outside it. The
# launcher reclaims every one of its ports again on start; this covers only the
# one the probe reads. `autoPort: false` in launch.json makes a port taken after
# this ran a failed start rather than a silent move to the next port.
#
# The port is the `app` configuration's `port` in .claude/launch.json: one
# source, read with sed. Every listener on it gets SIGTERM.
#
# Contract: exit 0 ALWAYS, and print nothing. Runs on a GUI-launched client's
# bare PATH (macOS bash 3.2, BSD userland); without lsof it does nothing.

set -uo pipefail
export LC_ALL=C

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0

EVENT="$(cat)"
SOURCE="$(printf '%s' "$EVENT" | tr -d '\n\r' |
  grep -oE '"source"[[:space:]]*:[[:space:]]*"[a-z]*"' | head -n1 |
  sed -E 's/.*"([a-z]*)"$/\1/')"
case "$SOURCE" in
  startup | clear) ;;
  *) exit 0 ;;
esac

LAUNCH="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/launch.json"
[ -f "$LAUNCH" ] || exit 0
command -v lsof >/dev/null 2>&1 || exit 0

PORT="$(tr -d '\n\r' <"$LAUNCH" |
  sed -nE 's/.*"name"[[:space:]]*:[[:space:]]*"app"[^}]*"port"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p')"
[ -n "$PORT" ] || exit 0

PIDS="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null)"
[ -n "$PIDS" ] || exit 0
# shellcheck disable=SC2086 # one pid per word, on purpose
kill $PIDS 2>/dev/null

# Up to five seconds for the listeners to let go, then SIGKILL what is left.
n=0
while [ "$n" -lt 50 ] && lsof -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
  sleep 0.1
  n=$((n + 1))
done
PIDS="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null)"
# shellcheck disable=SC2086
[ -z "$PIDS" ] || kill -9 $PIDS 2>/dev/null
exit 0
