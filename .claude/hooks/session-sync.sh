#!/usr/bin/env bash
# session-sync.sh — SessionStart hook.
#
# Brings the local copy up to date with GitHub's `main` at the start of a NEW
# chat (`source` startup or clear), when that is safe, and tells the model what
# arrived so it can say so in product words. Resume and compact are left
# alone, and so is a cloud session (CLAUDE_CODE_REMOTE=true), which already
# starts from the latest `main`.
#
# It is a hook rather than a model step ON PURPOSE: hooks run as the client,
# outside the Bash sandbox, which can neither fetch over ssh nor write the
# harness's own `.claude/hooks/` and `.claude/skills/`.
#
# After a fetch, the first matching row decides:
#   1. On `main`, behind `origin/main` and not diverged: fast-forward.
#   2. On a change branch whose every change `origin/main` has archived, with a
#      clean tree, nothing unpushed (HEAD is its upstream, or the upstream was
#      pruned), and `main` not diverged: switch to `main`, then fast-forward.
#   3. Anything else: nothing, silently. The next new chat retries.
# Git's own refusal to overwrite uncommitted work is the safety net for row 1;
# a switch deletes nothing, because the old branch stays put.
#
# A branch whose HEAD `origin/main` already contains (a merge commit) needs
# only its active folders under openspec/changes/ filed. Any other branch (a
# squash merge, or no merge yet) must carry at least one change, counting its
# active folders and the archived folders it has that its merge base with
# `origin/main` lacks, and every one must be filed. An active name is filed
# when `origin/main` has a dated `YYYY-MM-DD-<name>` folder for it; an
# archived folder, when `origin/main` has the same folder. Folder names are
# compared whole and literally.
#
# Output: after a move, one SessionStart additionalContext JSON object (kept
# well under the 10,000-character cap); after git refused the switch or the
# fast-forward, one plain line for the model; otherwise nothing.
#
# Contract: exit 0 ALWAYS. Runs on a GUI-launched client's bare PATH (macOS
# bash 3.2, BSD userland) and prefers the pinned toolchain when the project's
# `.devshell` out-link exists. No jq: the event is read with grep and the
# output is escaped with sed. Knob: SESSION_SYNC_TIMEOUT=<seconds> for the
# fetch (default 15).

set -uo pipefail
export LC_ALL=C

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0

if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.devshell/bin" ]; then
  PATH="$CLAUDE_PROJECT_DIR/.devshell/bin:$PATH"
fi

EVENT="$(cat)"
SOURCE="$(printf '%s' "$EVENT" | tr -d '\n\r' |
  grep -oE '"source"[[:space:]]*:[[:space:]]*"[a-z]*"' | head -n1 |
  sed -E 's/.*"([a-z]*)"$/\1/')"
case "$SOURCE" in
  startup | clear) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
TIMEOUT="${SESSION_SYNC_TIMEOUT:-15}"

# with_timeout <secs> <cmd...>: `timeout` when on PATH, else a watchdog. The
# watchdog's output goes to /dev/null ON PURPOSE: a `$(…)` capture around this
# would otherwise wait for the sleeping subshell to close the pipe.
with_timeout() {
  local secs="$1" pid wd rc
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  "$@" &
  pid=$!
  (
    sleep "$secs"
    kill "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid"
  rc=$?
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  return "$rc"
}

git remote get-url origin >/dev/null 2>&1 || exit 0
with_timeout "$TIMEOUT" git fetch --prune --quiet origin >/dev/null 2>&1 || exit 0
ORIGIN_MAIN="$(git rev-parse -q --verify 'origin/main^{commit}' 2>/dev/null)" || exit 0

# tree_dirs <ref> <path/>: the directory names directly under <path/> in <ref>'s tree.
tree_dirs() {
  git ls-tree -d --name-only "$1" "$2" 2>/dev/null | sed 's#.*/##' | grep -v '^\.' | sort
}

# all_in <lines> <set>: every non-empty line of <lines> is, literally, a line of <set>.
all_in() {
  printf '%s\n' "$1" | while IFS= read -r x; do
    [ -z "$x" ] || printf '%s\n' "$2" | grep -qxF -- "$x" || exit 1
  done
}

# ff_ok <commit>: the commit is origin/main or behind it, never diverged.
ff_ok() { git merge-base --is-ancestor "$1" "$ORIGIN_MAIN" 2>/dev/null; }

# refused <what> <git output>: the one line the model sees when git said no.
refused() {
  printf 'session-sync: tried to %s to match GitHub, and git refused, so nothing moved: %s. Do not bring this up unless the person asks why their copy is behind.\n' \
    "$1" "$(printf '%s' "$2" | tr '\n' ' ' | cut -c1-300)"
  exit 0
}

# fast_forward_main: the checked-out `main` to origin/main, unless already there.
fast_forward_main() {
  local out
  [ "$(git rev-parse HEAD 2>/dev/null)" = "$ORIGIN_MAIN" ] && return 0
  out="$(git merge --ff-only --quiet origin/main 2>&1)" || refused "fast-forward main" "$out"
}

BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || exit 0
OLD_HEAD="$(git rev-parse HEAD 2>/dev/null)" || exit 0
MAIN_BEFORE="$OLD_HEAD"
SWITCHED_FROM=""

if [ "$BRANCH" = main ]; then
  [ "$OLD_HEAD" = "$ORIGIN_MAIN" ] && exit 0
  ff_ok "$OLD_HEAD" || exit 0
else
  [ -z "$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)" ] || exit 0
  if UPSTREAM="$(git rev-parse -q --verify '@{upstream}' 2>/dev/null)"; then
    [ "$UPSTREAM" = "$OLD_HEAD" ] || exit 0
  else
    # No upstream ref: proceed only when one was configured and GitHub deleted it.
    git config --get "branch.$BRANCH.merge" >/dev/null 2>&1 || exit 0
  fi

  LOCAL_MAIN="$(git rev-parse -q --verify refs/heads/main 2>/dev/null)" || LOCAL_MAIN=""
  if [ -n "$LOCAL_MAIN" ]; then
    ff_ok "$LOCAL_MAIN" || exit 0
  fi

  ORIGIN_ARCHIVE="$(tree_dirs "$ORIGIN_MAIN" openspec/changes/archive/)"
  ACTIVE="$(tree_dirs HEAD openspec/changes/ | grep -vx archive)"
  OWN_ARCHIVED=""
  if ! git merge-base --is-ancestor HEAD "$ORIGIN_MAIN" 2>/dev/null; then
    MERGE_BASE="$(git merge-base HEAD "$ORIGIN_MAIN" 2>/dev/null)" || exit 0
    BASE_ARCHIVE="$(tree_dirs "$MERGE_BASE" openspec/changes/archive/)"
    OWN_ARCHIVED="$(tree_dirs HEAD openspec/changes/archive/ | while IFS= read -r a; do
      [ -n "$a" ] || continue
      printf '%s\n' "$BASE_ARCHIVE" | grep -qxF -- "$a" || printf '%s\n' "$a"
    done)"
    [ -n "$ACTIVE$OWN_ARCHIVED" ] || exit 0
  fi
  ORIGIN_FILED="$(printf '%s\n' "$ORIGIN_ARCHIVE" | sed -nE 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//p')"
  all_in "$ACTIVE" "$ORIGIN_FILED" || exit 0
  all_in "$OWN_ARCHIVED" "$ORIGIN_ARCHIVE" || exit 0

  out="$(git switch --quiet main 2>&1)" || refused "switch from the merged branch $BRANCH to main" "$out"
  MAIN_BEFORE="${LOCAL_MAIN:-$OLD_HEAD}"
  SWITCHED_FROM="$BRANCH"
fi
fast_forward_main

# --- tell the model ---------------------------------------------------------------

# json_text: stdin to the inside of a JSON string, lines joined with \n.
json_text() {
  tr -d '\000-\010\013-\037' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" |
    awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}

SWITCH_NOTE=""
if [ -n "$SWITCHED_FROM" ]; then
  SWITCH_NOTE="This chat started on the branch $SWITCHED_FROM, whose change GitHub's main has already merged and filed, so it is now on main instead. The old branch is untouched. That merged change is the person's own work: it gets no recap. "
fi

if [ "$MAIN_BEFORE" = "$ORIGIN_MAIN" ]; then
  MSG="SESSION SYNC: ${SWITCH_NOTE}main already matched GitHub, so nothing new arrived and there is nothing to tell the person."
else
  COUNT="$(git rev-list --count "$MAIN_BEFORE..$ORIGIN_MAIN" 2>/dev/null || echo 0)"
  LOG="$(git log --oneline --no-decorate -n 40 "$MAIN_BEFORE..$ORIGIN_MAIN" 2>/dev/null | cut -c1-160)"
  FILES="$(git diff --name-only "$MAIN_BEFORE" "$ORIGIN_MAIN" 2>/dev/null)"
  LOCKS="$(printf '%s\n' "$FILES" | grep -xE 'pnpm-lock\.yaml|flake\.lock' | tr '\n' ' ' | sed 's/ $//')"
  DOCS="$(printf '%s\n' "$FILES" | grep -E '(^|/)AGENTS\.md$|^\.claude/output-styles/' | head -n 20 | tr '\n' ' ' | sed 's/ $//')"

  MSG="SESSION SYNC: this copy was behind GitHub and has been brought up to date at the start of this chat. ${SWITCH_NOTE}main moved from $MAIN_BEFORE to $ORIGIN_MAIN ($COUNT commits; newest 40 at most below, read the rest with git).

In your first reply, before anything else, tell the person in one or two plain product lines what is different for them now. Read git log --stat $MAIN_BEFORE..$ORIGIN_MAIN and the diffs that matter to work it out. Changes that alter nothing they would see or do get at most one line, such as: picked up some behind-the-scenes improvements. A change the person built and merged themselves gets no recap."
  if [ -n "$LOCKS" ]; then
    MSG="$MSG

The update changed $LOCKS: refresh dependencies before running any check (pnpm install for pnpm-lock.yaml; for flake.lock, the dev shell's tools are stale until it is re-entered, and .devshell, when present, is rebuilt with nix build .#toolchain --out-link .devshell)."
  fi
  if [ -n "$DOCS" ]; then
    MSG="$MSG

The update changed $DOCS. Those were loaded at launch, before this sync: read the new versions now; they replace what this chat loaded. Skills, commands and the settings' hooks are watched, so they are already current."
  fi
  MSG="$MSG

Commits:
$LOG"
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(printf '%s\n' "$MSG" | json_text)"
exit 0
