#!/usr/bin/env bash
# test-session-sync.sh — prove session-sync.sh brings a local copy up to date
# exactly when its table says to, and leaves it alone otherwise.
#
# Every state is a throwaway git repository built here, with a bare "origin"
# beside it and a second clone of that origin standing in for GitHub, where
# merges and harness updates land. The suite runs once on the host's tools
# and, when the `.devshell` out-link exists, again with the pinned toolchain
# on PATH.

set -uo pipefail
export LC_ALL=C
unset CLAUDE_PROJECT_DIR CLAUDE_CODE_REMOTE SESSION_SYNC_TIMEOUT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$ROOT/.claude/hooks/session-sync.sh}"
[ -f "$HOOK" ] || {
  echo "Missing: $HOOK"
  exit 1
}

PASS=0
FAIL=0
pass() {
  printf '  \033[32mPASS\033[0m  %s\n' "$1"
  PASS=$((PASS + 1))
}
fail() {
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  FAIL=$((FAIL + 1))
}

# Fixtures go to the sandbox-writable temp dir first, and git never walks up
# out of $TDIR looking for a repository: a fixture that failed to initialize
# must never resolve to the real one.
TDIR="$(mktemp -d "${TMPDIR:-/tmp}/session-sync-test.XXXXXX" 2>/dev/null)" ||
  TDIR="$(mktemp -d 2>/dev/null)" ||
  TDIR="$(mktemp -d .session-sync-test.XXXXXX)"
[ -n "$TDIR" ] && [ -d "$TDIR" ] || {
  echo "Could not create a scratch directory."
  exit 1
}
TDIR="$(cd "$TDIR" && pwd -P)"
export GIT_CEILING_DIRECTORIES="$TDIR"
trap 'rm -rf "$TDIR"' EXIT

# --- fixtures -------------------------------------------------------------------

N=0

git_identity() {
  git config user.email test@example.org
  git config user.name test
  git config commit.gpgsign false
}

# make_repo: a fresh repository on `main` with an empty archive and one spec.
# Sets R to its path; stops the suite if the repository could not be created.
R=""
make_repo() {
  N=$((N + 1))
  R="$TDIR/repo$N"
  mkdir -p "$R"
  (
    cd "$R" || exit 1
    git init -q . >/dev/null 2>&1 || exit 1
    git checkout -q -b main 2>/dev/null || true
    git_identity
    printf '# App\n' >README.md
    mkdir -p openspec/changes/archive openspec/specs/app
    printf '# app\n' >openspec/specs/app/spec.md
    touch openspec/changes/archive/.keep
    git add -A
    git commit -qm "init" >/dev/null
  ) || {
    echo "Could not build the fixture repository at $R."
    exit 1
  }
  [ "$(cd "$R" && git rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$R" && pwd -P)" ] || {
    echo "The fixture at $R is not its own repository; stopping before anything touches the real one."
    exit 1
  }
}

# add_origin <repo>: a bare origin beside it, main pushed and tracking, and a
# clone of it at <repo>.gh standing in for GitHub.
add_origin() {
  git init -q --bare "$1.origin" >/dev/null 2>&1
  git -C "$1.origin" symbolic-ref HEAD refs/heads/main
  (cd "$1" && git remote add origin "$1.origin" && git push -q -u origin main >/dev/null 2>&1)
  git clone -q "$1.origin" "$1.gh" >/dev/null 2>&1
  (cd "$1.gh" && git_identity)
}

# add_change <repo> <name> <proposing|planned|built> [dir]
add_change() {
  local root="${4:-openspec/changes}"
  local dir="$1/$root/$2"
  mkdir -p "$dir"
  printf '# Discovery\n' >"$dir/discovery.md"
  printf '# Proposal\n\n## Why\n\nPeople want %s.\n' "$2" >"$dir/proposal.md"
  [ "$3" = "proposing" ] && return 0
  mkdir -p "$dir/specs/$2"
  printf '## ADDED Requirements\n' >"$dir/specs/$2/spec.md"
  printf '# Design\n' >"$dir/design.md"
  case "$3" in
    planned) printf '## 1. Work\n\n- [ ] 1.1 First\n' >"$dir/tasks.md" ;;
    built) printf '## 1. Work\n\n- [x] 1.1 First\n' >"$dir/tasks.md" ;;
  esac
}

commit_all() { (cd "$1" && git add -A && git commit -qm "${2:-work}" >/dev/null); }

# github_commit <repo> <path> <subject>: a harness update landing on GitHub's main.
github_commit() {
  (
    cd "$1.gh" || exit 1
    git pull -q --ff-only origin main >/dev/null 2>&1
    mkdir -p "$(dirname "$2")"
    printf 'update %s\n' "$3" >>"$2"
    git add -A && git commit -qm "$3" >/dev/null && git push -q origin main >/dev/null 2>&1
  )
}

# github_merge <repo> <branch>: the person's click on GitHub's merge button.
github_merge() {
  (
    cd "$1.gh" || exit 1
    git pull -q --ff-only origin main >/dev/null 2>&1
    git fetch -q origin >/dev/null 2>&1
    git merge -q --no-ff -m "Merge $2" "origin/$2" >/dev/null 2>&1 && git push -q origin main >/dev/null 2>&1
  )
}

# merged_branch <repo> <branch> <change>: a change built and archived on its
# own branch, pushed, and merged on GitHub. Leaves the repo on that branch.
merged_branch() {
  (cd "$1" && git checkout -q -b "$2")
  add_change "$1" "$3" built
  commit_all "$1" "build $3"
  (cd "$1" && git mv "openspec/changes/$3" "openspec/changes/archive/2026-10-19-$3")
  commit_all "$1" "file $3"
  (cd "$1" && git push -q -u origin "$2" >/dev/null 2>&1)
  github_merge "$1" "$2"
}

# --- assertions -----------------------------------------------------------------

OUT=""
RC=0
# run_hook <repo> <source> [VAR=value ...]
run_hook() {
  local dir="$1" src="$2"
  shift 2
  OUT="$(printf '{"session_id":"t","hook_event_name":"SessionStart","source":"%s"}' "$src" |
    env CLAUDE_PROJECT_DIR="$dir" "$@" bash "$HOOK" 2>"$TDIR/stderr")"
  RC=$?
}

head_of() { (cd "$1" && git rev-parse "${2:-HEAD}"); }
branch_of() { (cd "$1" && git symbolic-ref --short -q HEAD || echo detached); }

check_rc0() {
  if [ "$RC" -eq 0 ]; then pass "$1"; else
    fail "$1 (rc=$RC; stderr: $(head -c 300 "$TDIR/stderr" | tr '\n' ' '))"
  fi
}
check_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi
}
check_silent() {
  if [ -z "$OUT" ]; then pass "$1"; else fail "$1 (said: $(printf '%s' "$OUT" | head -c 200))"; fi
}
check_says() {
  if printf '%s' "$OUT" | grep -qE -- "$2"; then pass "$1"; else
    fail "$1 (expected /$2/ in: $(printf '%s' "$OUT" | head -c 200))"
  fi
}
check_not_says() {
  if printf '%s' "$OUT" | grep -qE -- "$2"; then fail "$1 (found /$2/)"; else pass "$1"; fi
}
# check_json: the output is one well-formed JSON object, when a parser is around.
check_json() {
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | type == "string"' >/dev/null 2>&1; then
      pass "$1"
    else
      fail "$1 (not valid JSON)"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$OUT" | python3 -c 'import json,sys; assert isinstance(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"], str)' 2>/dev/null; then
      pass "$1"
    else
      fail "$1 (not valid JSON)"
    fi
  else
    pass "$1 (no JSON parser on PATH; shape only)"
  fi
}

run_suite() {
  echo
  echo "Session sync tests ($1)"
  echo "------------------"

  local r old new

  # --- row 1: main behind GitHub -------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  github_commit "$r" docs/notes.md 'feat: a "quoted" harness update'
  old="$(head_of "$r")"
  new="$(head_of "$r.origin" main)"
  run_hook "$r" startup
  check_rc0 "main behind: exit 0"
  check_eq "main behind: main is at GitHub's main" "$(head_of "$r")" "$new"
  check_says "main behind: context for the model" '"hookEventName":"SessionStart","additionalContext":"SESSION SYNC'
  check_says "main behind: names the old commit" "$old"
  check_says "main behind: names the new commit" "$new"
  check_says "main behind: lists the commit" 'a \\"quoted\\" harness update'
  check_says "main behind: asks for a product summary" 'first reply'
  check_not_says "main behind: no dependency refresh" 'refresh dependencies'
  check_not_says "main behind: no re-read" 'read the new versions'
  check_json "main behind: well-formed JSON"
  run_hook "$r" startup
  check_silent "main current: silent"

  # --- row 1 via clear, with lockfiles and instructions touched ---------------------
  github_commit "$r" pnpm-lock.yaml "chore: bump dependencies"
  github_commit "$r" packages/db/AGENTS.md "docs: db rules"
  github_commit "$r" .claude/output-styles/Guided.md "style: tweak"
  run_hook "$r" clear
  check_eq "clear: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"
  check_says "lockfile: asks for a dependency refresh" 'changed pnpm-lock\.yaml: refresh dependencies'
  check_says "instructions: asks to re-read" 'changed \.claude/output-styles/Guided\.md packages/db/AGENTS\.md\. .*read the new versions'
  check_json "lockfile: well-formed JSON"

  # --- not a new chat; cloud; no remote; fetch fails --------------------------------
  github_commit "$r" docs/notes.md "feat: another"
  old="$(head_of "$r")"
  run_hook "$r" resume
  check_silent "resume: silent"
  check_eq "resume: nothing moved" "$(head_of "$r")" "$old"
  run_hook "$r" compact
  check_eq "compact: nothing moved" "$(head_of "$r")" "$old"
  run_hook "$r" startup CLAUDE_CODE_REMOTE=true
  check_silent "cloud: silent"
  check_eq "cloud: nothing moved" "$(head_of "$r")" "$old"
  (cd "$r" && git remote set-url origin "$TDIR/does-not-exist")
  run_hook "$r" startup SESSION_SYNC_TIMEOUT=5
  check_rc0 "fetch fails: exit 0"
  check_silent "fetch fails: silent"
  check_eq "fetch fails: nothing moved" "$(head_of "$r")" "$old"
  (cd "$r" && git remote set-url origin "$r.origin")
  printf 'not json\n' | env CLAUDE_PROJECT_DIR="$r" bash "$HOOK" >/dev/null 2>&1
  check_eq "unparsable event: nothing moved" "$(head_of "$r")" "$old"

  make_repo
  run_hook "$R" startup
  check_rc0 "no remote: exit 0"
  check_silent "no remote: silent"

  # --- main diverged -------------------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  github_commit "$r" docs/notes.md "feat: upstream"
  printf 'local\n' >"$r/local.md"
  commit_all "$r" "local only"
  old="$(head_of "$r")"
  run_hook "$r" startup
  check_silent "main diverged: silent"
  check_eq "main diverged: nothing moved" "$(head_of "$r")" "$old"

  # --- uncommitted proposal on main ---------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  github_commit "$r" docs/notes.md "feat: upstream"
  add_change "$r" add-todo proposing
  run_hook "$r" startup
  check_eq "proposal, no collision: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"
  check_eq "proposal, no collision: proposal kept" "$(cat "$r/openspec/changes/add-todo/proposal.md" 2>/dev/null | head -n1)" "# Proposal"

  github_commit "$r" openspec/changes/add-todo/proposal.md "feat: same path upstream"
  old="$(head_of "$r")"
  run_hook "$r" startup
  check_rc0 "proposal collides: exit 0"
  check_eq "proposal collides: nothing moved" "$(head_of "$r")" "$old"
  check_eq "proposal collides: proposal kept" "$(head -n1 "$r/openspec/changes/add-todo/proposal.md")" "# Proposal"
  check_says "proposal collides: one line for the model" '^session-sync: tried to fast-forward main'
  check_eq "proposal collides: exactly one line" "$(printf '%s\n' "$OUT" | grep -c .)" 1

  # --- row 2: merged change branch ----------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  merged_branch "$r" feat/export export-tasks
  github_commit "$r" docs/notes.md "feat: harness update after the merge"
  old="$(head_of "$r" main)"
  run_hook "$r" startup
  check_rc0 "merged branch: exit 0"
  check_eq "merged branch: now on main" "$(branch_of "$r")" main
  check_eq "merged branch: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"
  check_eq "merged branch: old branch kept" "$(cd "$r" && git rev-parse -q --verify refs/heads/feat/export >/dev/null && echo yes)" yes
  check_says "merged branch: names the branch" 'branch feat/export'
  check_says "merged branch: range starts at the old main" "$old"
  check_json "merged branch: well-formed JSON"

  # upstream pruned because GitHub deleted the merged branch; local main missing
  make_repo
  r="$R"
  add_origin "$r"
  merged_branch "$r" feat/export export-tasks
  (cd "$r.gh" && git push -q origin --delete feat/export >/dev/null 2>&1)
  (cd "$r" && git branch -q -D main)
  run_hook "$r" startup
  check_eq "pruned upstream, no local main: now on main" "$(branch_of "$r")" main
  check_eq "pruned upstream, no local main: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"

  # already-current main: switch, nothing new to tell
  make_repo
  r="$R"
  add_origin "$r"
  merged_branch "$r" feat/export export-tasks
  (cd "$r" && git fetch -q origin && git branch -q -f main origin/main)
  run_hook "$r" startup
  check_eq "merged, main current: now on main" "$(branch_of "$r")" main
  check_says "merged, main current: nothing to tell" 'nothing new arrived'

  # squash merge: the branch is not contained in GitHub's main, its archive is
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b feat/export)
  add_change "$r" export-tasks built
  commit_all "$r" "build export-tasks"
  (cd "$r" && git mv openspec/changes/export-tasks openspec/changes/archive/2026-10-19-export-tasks)
  commit_all "$r" "file export-tasks"
  (cd "$r" && git push -q -u origin feat/export >/dev/null 2>&1)
  (cd "$r.gh" && git fetch -q origin && git merge -q --squash origin/feat/export >/dev/null 2>&1 &&
    git commit -qm "Export tasks (#1)" >/dev/null && git push -q origin main >/dev/null 2>&1)
  run_hook "$r" startup
  check_eq "squash-merged branch: now on main" "$(branch_of "$r")" main
  check_eq "squash-merged branch: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"

  # squash merge of a change whose archived name has a space
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b feat/big)
  add_change "$r" "big change" built
  commit_all "$r" "build big change"
  (cd "$r" && git mv "openspec/changes/big change" "openspec/changes/archive/2026-10-19-big change")
  commit_all "$r" "file big change"
  (cd "$r" && git push -q -u origin feat/big >/dev/null 2>&1)
  (cd "$r.gh" && git fetch -q origin && git merge -q --squash origin/feat/big >/dev/null 2>&1 &&
    git commit -qm "Big change (#2)" >/dev/null && git push -q origin main >/dev/null 2>&1)
  run_hook "$r" startup
  check_eq "squash-merged, spaced name: now on main" "$(branch_of "$r")" main

  # merged on GitHub but never filed: /Align's case, not this hook's
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b feat/export)
  add_change "$r" export-tasks built
  commit_all "$r" "build export-tasks"
  (cd "$r" && git push -q -u origin feat/export >/dev/null 2>&1)
  github_merge "$r" feat/export
  run_hook "$r" startup
  check_silent "merged, never filed: silent"
  check_eq "merged, never filed: still on the branch" "$(branch_of "$r")" feat/export

  # a change name is matched literally: `v1.0` is not filed by a `v1x0` archive
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b feat/v1)
  add_change "$r" v1.0 built
  commit_all "$r" "build v1.0"
  (cd "$r" && git push -q -u origin feat/v1 >/dev/null 2>&1)
  github_merge "$r" feat/v1
  github_commit "$r" openspec/changes/archive/2026-10-19-v1x0/proposal.md "file v1x0"
  run_hook "$r" startup
  check_silent "lookalike archive: silent"
  check_eq "lookalike archive: still on the branch" "$(branch_of "$r")" feat/v1

  # a change name with a space is one name, filed on GitHub after the merge
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b feat/big)
  add_change "$r" "big change" built
  commit_all "$r" "build big change"
  (cd "$r" && git push -q -u origin feat/big >/dev/null 2>&1)
  github_merge "$r" feat/big
  (cd "$r.gh" && git mv "openspec/changes/big change" "openspec/changes/archive/2026-10-19-big change" &&
    git commit -qm "file big change" >/dev/null && git push -q origin main >/dev/null 2>&1)
  run_hook "$r" startup
  check_eq "spaced name, filed: now on main" "$(branch_of "$r")" main
  check_eq "spaced name, filed: main is at GitHub's main" "$(head_of "$r")" "$(head_of "$r.origin" main)"

  # --- row 2 refusals ---------------------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  merged_branch "$r" feat/export export-tasks
  printf 'scratch\n' >"$r/scratch.md"
  run_hook "$r" startup
  check_silent "merged, dirty tree: silent"
  check_eq "merged, dirty tree: still on the branch" "$(branch_of "$r")" feat/export
  rm "$r/scratch.md"

  printf 'more\n' >"$r/more.md"
  commit_all "$r" "unpushed"
  run_hook "$r" startup
  check_silent "merged, unpushed commit: silent"
  check_eq "merged, unpushed commit: still on the branch" "$(branch_of "$r")" feat/export

  make_repo
  r="$R"
  add_origin "$r"
  merged_branch "$r" feat/export export-tasks
  (cd "$r" && git checkout -q main && printf 'local\n' >local.md && git add -A && git commit -qm "local only" && git checkout -q feat/export)
  run_hook "$r" startup
  check_silent "merged, main diverged: silent"
  check_eq "merged, main diverged: still on the branch" "$(branch_of "$r")" feat/export

  # --- mid-change and never-pushed branches; detached --------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  github_commit "$r" docs/notes.md "feat: upstream"
  (cd "$r" && git checkout -q -b feat/todo)
  add_change "$r" add-todo planned
  commit_all "$r" "plan add-todo"
  run_hook "$r" startup
  check_silent "never pushed: silent"
  check_eq "never pushed: still on the branch" "$(branch_of "$r")" feat/todo
  (cd "$r" && git push -q -u origin feat/todo >/dev/null 2>&1)
  old="$(head_of "$r")"
  run_hook "$r" startup
  check_silent "mid-change: silent"
  check_eq "mid-change: still on the branch" "$(branch_of "$r")" feat/todo
  check_eq "mid-change: nothing moved" "$(head_of "$r")" "$old"

  (cd "$r" && git checkout -q --detach HEAD)
  run_hook "$r" startup
  check_silent "detached: silent"
  check_eq "detached: still detached" "$(branch_of "$r")" detached

  # a branch carrying no change at all
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b chore/x && printf 'x\n' >x.md && git add -A && git commit -qm x && git push -q -u origin chore/x >/dev/null 2>&1)
  github_commit "$r" docs/notes.md "feat: upstream"
  run_hook "$r" startup
  check_silent "no change on branch: silent"
  check_eq "no change on branch: still on the branch" "$(branch_of "$r")" chore/x
}

SAVED_PATH="$PATH"
run_suite "host PATH"

if [ -d "$ROOT/.devshell/bin" ]; then
  PATH="$ROOT/.devshell/bin:$SAVED_PATH"
  run_suite "pinned toolchain via .devshell"
else
  echo
  echo "  (no .devshell out-link; pinned-toolchain pass skipped)"
fi

echo
echo "  $PASS passed, $FAIL failed"
echo
[ "$FAIL" -eq 0 ]
