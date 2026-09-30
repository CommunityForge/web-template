#!/usr/bin/env bash
# test-align-probe.sh — prove align-probe.sh reports each project state it is
# asked about, and mutates nothing while doing so.
#
# Every state is a throwaway git repository built here, with a bare "origin"
# beside it where a remote matters. A fake `gh` first on PATH answers the
# probe's GitHub calls with canned post-jq output, so the real network and the
# real wizard are never touched. The suite runs once on the host's tools and,
# when the `.devshell` out-link exists, again with the pinned toolchain on
# PATH — the GNU-vs-BSD `stat` and `timeout` fallbacks are what the second
# pass exercises.

set -uo pipefail
export LC_ALL=C
unset CLAUDE_PROJECT_DIR CLAUDE_CODE_REMOTE
unset ALIGN_PROBE_NO_GITHUB ALIGN_PROBE_NO_FETCH ALIGN_PROBE_WIZARD ALIGN_PROBE_TIMEOUT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="${1:-$ROOT/bin/align-probe.sh}"
[ -f "$PROBE" ] || {
  echo "Missing: $PROBE"
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

# Fixtures go to the sandbox-writable temp dir first ($TMPDIR is what a
# sandboxed agent's shell may write; /var/folders is not), then the system
# one, then the repo. Every fixture is checked to be its own repository before
# use, and git never walks up out of $TDIR looking for one: a fixture that
# failed to initialize must never resolve to the real repository.
TDIR="$(mktemp -d "${TMPDIR:-/tmp}/align-probe-test.XXXXXX" 2>/dev/null)" ||
  TDIR="$(mktemp -d 2>/dev/null)" ||
  TDIR="$(mktemp -d .align-probe-test.XXXXXX)"
[ -n "$TDIR" ] && [ -d "$TDIR" ] || {
  echo "Could not create a scratch directory."
  exit 1
}
TDIR="$(cd "$TDIR" && pwd -P)"
export GIT_CEILING_DIRECTORIES="$TDIR"
trap 'rm -rf "$TDIR"' EXIT

# --- the fake gh --------------------------------------------------------------
# Logs every invocation to FAKE_GH_LOG and answers from environment variables,
# already in the shape the probe's --jq programs would produce.
mkdir -p "$TDIR/fakebin"
cat >"$TDIR/fakebin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_GH_LOG:-/dev/null}"
case "$1 $2" in
  "auth status") exit "${FAKE_GH_AUTH_RC:-0}" ;;
  "pr list")
    [ "${FAKE_GH_PR_RC:-0}" -eq 0 ] || exit "$FAKE_GH_PR_RC"
    [ -n "${FAKE_GH_PRS:-}" ] && printf '%s\n' "$FAKE_GH_PRS"
    exit 0
    ;;
  "run list")
    case "$*" in
      *preview.yml*) [ -n "${FAKE_GH_RUN_ID:-}" ] && printf '%s\n' "$FAKE_GH_RUN_ID" ;;
      *deploy.yml*) [ -n "${FAKE_GH_DEPLOY:-}" ] && printf '%s\n' "$FAKE_GH_DEPLOY" ;;
    esac
    exit 0
    ;;
  "run view")
    [ -n "${FAKE_GH_FAILED_STEP:-}" ] && printf '%s\n' "$FAKE_GH_FAILED_STEP"
    exit 0
    ;;
esac
exit 1
GH
chmod +x "$TDIR/fakebin/gh"

# A PATH with every tool the probe needs except gh, for the `missing` case.
mkdir -p "$TDIR/nogh"
for tool in bash sh git grep sed awk cut tr sort uniq head tail wc date stat mktemp uname cat ls \
  basename dirname sleep timeout env find rm mkdir touch printf test expr; do
  p="$(command -v "$tool" 2>/dev/null)" && ln -s "$p" "$TDIR/nogh/$tool" 2>/dev/null
done

# --- fixtures -------------------------------------------------------------------

TAB="$(printf '\t')"
N=0

# make_repo: a fresh repository on `main` with the files the probe reads —
# `replaceme` still in place, a spec, one source file per area, and a fake
# Setup.command that reports two always-present todo items. Sets R to its
# path; stops the suite if the repository could not be created.
R=""
make_repo() {
  N=$((N + 1))
  R="$TDIR/repo$N"
  mkdir -p "$R"
  (
    cd "$R" || exit 1
    git init -q . >/dev/null 2>&1 || exit 1
    git checkout -q -b main 2>/dev/null || true
    git config user.email test@example.org
    git config user.name test
    git config commit.gpgsign false
    printf 'name = "replaceme";\n' >flake.nix
    printf '{ "name": "@replaceme/root" }\n' >package.json
    printf '# App\n' >README.md
    mkdir -p openspec/changes/archive openspec/specs/app apps/frontend/src packages/lib/src
    printf '# app\n' >openspec/specs/app/spec.md
    printf 'export {}\n' >apps/frontend/src/app.ts
    printf 'export {}\n' >packages/lib/src/index.ts
    touch openspec/changes/archive/.keep
    cat >Setup.command <<'WIZ'
#!/usr/bin/env bash
if [ "${FAKE_WIZARD_RC:-0}" -ne 0 ]; then
  printf '  ⚠ Nix is not installed.\n'
  exit "$FAKE_WIZARD_RC"
fi
printf '\n  ✓ Setup complete\n\n'
printf '  ⚠ still to do by hand:\n'
printf '    - nix develop -c pnpm check\n'
printf '    - GitHub access: sign in (.devshell/bin/gh auth login --web) and connect the folder\n'
printf '\n'
WIZ
    chmod +x Setup.command
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

# add_origin <repo>: a bare origin beside it, main pushed and tracking.
add_origin() {
  git init -q --bare "$1.origin" >/dev/null 2>&1
  (cd "$1" && git remote add origin "$1.origin" && git push -q -u origin main >/dev/null 2>&1)
}

# github_origin <repo>: point origin at a GitHub-shaped URL. Remote-tracking
# refs from earlier pushes stay; callers pass ALIGN_PROBE_NO_FETCH=1.
github_origin() {
  (cd "$1" && git remote set-url origin git@github.com:acme/app.git)
}

# add_change <repo> <name> <empty|proposing|planned|building|built> [dir]
add_change() {
  local root="${4:-openspec/changes}"
  local dir="$1/$root/$2"
  mkdir -p "$dir"
  [ "$3" = "empty" ] && return 0
  printf '# Discovery\n' >"$dir/discovery.md"
  printf '# Proposal\n\n## Why\n\nPeople want %s.\n' "$2" >"$dir/proposal.md"
  [ "$3" = "proposing" ] && return 0
  mkdir -p "$dir/specs/$2"
  printf '## ADDED Requirements\n' >"$dir/specs/$2/spec.md"
  printf '# Design\n' >"$dir/design.md"
  case "$3" in
    planned) printf '## 1. Work\n\n- [ ] 1.1 First\n- [ ] 1.2 Second\n- [ ] 1.3 Third\n' >"$dir/tasks.md" ;;
    building) printf '## 1. Work\n\n- [x] 1.1 First\n- [ ] 1.2 Second\n- [ ] 1.3 Third\n' >"$dir/tasks.md" ;;
    built) printf '## 1. Work\n\n- [x] 1.1 First\n- [X] 1.2 Second\n  - [x] 1.3 Third\n' >"$dir/tasks.md" ;;
  esac
}

commit_all() { (cd "$1" && git add -A && git commit -qm "${2:-work}" >/dev/null); }

# --- assertions -----------------------------------------------------------------

OUT=""
RC=0
# probe <repo> [VAR=value ...]: run the probe in that repo with extra env.
probe() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && env "$@" bash "$PROBE" 2>"$TDIR/stderr")"
  RC=$?
}

key() {
  local esc
  esc="$(printf '%s' "$1" | sed 's/[.[*^$\\]/\\&/g')"
  printf '%s\n' "$OUT" | sed -n "s/^$esc=//p" | head -n1
}
check_key() {
  local got
  got="$(key "$2")"
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1 ($2: expected '$3', got '$got')"; fi
}
check_match() {
  local got
  got="$(key "$2")"
  if printf '%s' "$got" | grep -qE "$3"; then pass "$1"; else fail "$1 ($2: expected /$3/, got '$got')"; fi
}
check_absent() {
  if printf '%s\n' "$OUT" | grep -qE "$2"; then fail "$1 (found /$2/)"; else pass "$1"; fi
}
check_rc0() {
  if [ "$RC" -eq 0 ]; then pass "$1"; else
    fail "$1 (rc=$RC; stderr: $(head -c 300 "$TDIR/stderr" | tr '\n' ' '))"
  fi
}

run_suite() {
  echo
  echo "Align probe tests ($1)"
  echo "-----------------"

  local r log

  # --- clean main ---------------------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  local before after
  before="$(cd "$r" && git status --porcelain=v1 --untracked-files=all)"
  probe "$r" ALIGN_PROBE_WIZARD=run
  after="$(cd "$r" && git status --porcelain=v1 --untracked-files=all)"
  check_rc0 "clean main: exit 0"
  check_key "clean main: probe.version" probe.version 1
  check_key "clean main: probe.errors" probe.errors none
  check_match "clean main: session.kind is a desktop" session.kind '^desktop-(mac|linux)$'
  check_key "clean main: session.devshell" session.devshell no
  check_key "clean main: git.branch" git.branch main
  check_key "clean main: git.on_main" git.on_main yes
  check_key "clean main: git.upstream" git.upstream origin/main
  check_key "clean main: git.ahead" git.ahead 0
  check_key "clean main: git.behind" git.behind 0
  check_key "clean main: git.ahead_of_origin_main" git.ahead_of_origin_main 0
  check_key "clean main: git.behind_origin_main" git.behind_origin_main 0
  check_key "clean main: git.fetch" git.fetch ok
  check_key "clean main: git.dirty.openspec" git.dirty.openspec 0
  check_key "clean main: git.dirty.code" git.dirty.code 0
  check_key "clean main: git.dirty.other" git.dirty.other 0
  check_key "clean main: git.dirty.untracked" git.dirty.untracked 0
  check_key "clean main: change.count" change.count 0
  check_key "clean main: branch.count" branch.count 0
  check_key "clean main: repo.github" repo.github none
  check_key "clean main: repo.replaceme" repo.replaceme yes
  check_key "clean main: repo.docs_context" repo.docs_context missing
  check_key "clean main: github.status" github.status no-remote
  check_absent "clean main: no pr.* keys" '^pr\.'
  check_key "clean main: deploy.main" deploy.main unavailable
  check_key "clean main: wizard.status" wizard.status ok
  check_key "clean main: wizard.todo.count" wizard.todo.count 2
  check_key "clean main: wizard.todo.1" wizard.todo.1 "nix develop -c pnpm check"
  check_match "clean main: wizard.todo.2" wizard.todo.2 '^GitHub access'
  check_match "clean main: probe.duration_s" probe.duration_s '^[0-9]+$'
  if [ "$before" = "$after" ]; then pass "clean main: git status unchanged"; else fail "clean main: git status changed"; fi

  # --- wizard variants ----------------------------------------------------------
  probe "$r" ALIGN_PROBE_WIZARD=run FAKE_WIZARD_RC=1
  check_key "wizard stops early: wizard.status" wizard.status stopped-early
  check_key "wizard stops early: wizard.todo.count" wizard.todo.count 0
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "wizard skip: wizard.status" wizard.status skipped
  check_absent "wizard skip: no todo keys" '^wizard\.todo\.[0-9]'
  rm "$r/Setup.command"
  probe "$r" ALIGN_PROBE_WIZARD=run
  check_key "wizard absent: wizard.status" wizard.status absent
  (cd "$r" && git checkout -q -- Setup.command)

  # --- proposing, unsaved -------------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  add_change "$r" add-todo proposing
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_rc0 "proposing: exit 0"
  check_key "proposing: change.count" change.count 1
  check_key "proposing: change.1.name" change.1.name add-todo
  check_key "proposing: change.1.stage" change.1.stage proposing
  check_key "proposing: change.1.artifacts" change.1.artifacts discovery,proposal
  check_key "proposing: change.1.tasks_done" change.1.tasks_done 0
  check_key "proposing: change.1.tasks_total" change.1.tasks_total 0
  check_key "proposing: change.1.age_days" change.1.age_days 0
  check_key "proposing: change.1.branches" change.1.branches none
  check_key "proposing: git.dirty.untracked" git.dirty.untracked 2
  check_key "proposing: git.dirty.openspec" git.dirty.openspec 0

  # --- empty change folder ------------------------------------------------------
  add_change "$r" blank empty
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "empty folder: change.count" change.count 2
  check_key "empty folder: change.2.stage" change.2.stage empty
  check_key "empty folder: change.2.artifacts" change.2.artifacts none

  # --- planned, committed on main -----------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  add_change "$r" add-todo planned
  commit_all "$r" "plan add-todo"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "planned: change.1.stage" change.1.stage planned
  check_key "planned: change.1.tasks_done" change.1.tasks_done 0
  check_key "planned: change.1.tasks_total" change.1.tasks_total 3
  check_key "planned: change.1.artifacts" change.1.artifacts discovery,proposal,specs,design,tasks
  check_key "planned: change.1.branches" change.1.branches main
  check_key "planned: git.ahead_of_origin_main" git.ahead_of_origin_main 1
  check_key "planned: git.dirty.untracked" git.dirty.untracked 0

  # --- building on a pushed branch with PR 42 and a preview ---------------------
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b add-todo)
  add_change "$r" add-todo building
  commit_all "$r" "build add-todo"
  (cd "$r" && git push -q -u origin add-todo >/dev/null 2>&1)
  github_origin "$r"
  log="$TDIR/gh$N.log"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_LOG="$log" \
    FAKE_GH_PRS="42${TAB}add-todo${TAB}Add todo${TAB}false${TAB}3${TAB}1${TAB}pass${TAB}https://pr-42.example.workers.dev"
  check_rc0 "building+PR: exit 0"
  check_key "building+PR: repo.github" repo.github acme/app
  check_key "building+PR: github.status" github.status ok
  check_key "building+PR: git.fetch" git.fetch skipped
  check_key "building+PR: git.on_main" git.on_main no
  check_key "building+PR: git.upstream" git.upstream origin/add-todo
  check_key "building+PR: change.1.stage" change.1.stage building
  check_key "building+PR: change.1.tasks_done" change.1.tasks_done 1
  check_key "building+PR: change.1.tasks_total" change.1.tasks_total 3
  check_key "building+PR: change.1.branches" change.1.branches add-todo,origin/add-todo
  check_key "building+PR: branch.count excludes the current branch" branch.count 0
  check_key "building+PR: pr.count" pr.count 1
  check_key "building+PR: pr.1.number" pr.1.number 42
  check_key "building+PR: pr.1.branch" pr.1.branch add-todo
  check_key "building+PR: pr.1.change" pr.1.change add-todo
  check_key "building+PR: pr.1.title" pr.1.title "Add todo"
  check_key "building+PR: pr.1.draft" pr.1.draft no
  check_key "building+PR: pr.1.age_days" pr.1.age_days 3
  check_key "building+PR: pr.1.updated_days" pr.1.updated_days 1
  check_key "building+PR: pr.1.checks" pr.1.checks pass
  check_key "building+PR: pr.1.preview_url" pr.1.preview_url https://pr-42.example.workers.dev
  check_key "building+PR: pr.1.preview_failed_step" pr.1.preview_failed_step none
  check_key "building+PR: pr.1.archived" pr.1.archived no
  if grep -q -- "-R acme/app" "$log"; then pass "building+PR: gh is always told the repo"; else fail "building+PR: gh call lacks -R acme/app"; fi
  if grep -q "^run view" "$log"; then fail "building+PR: no drill-down when checks pass"; else pass "building+PR: no drill-down when checks pass"; fi

  # --- built with a pending PR --------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b add-todo)
  add_change "$r" add-todo built
  commit_all "$r" "finish add-todo"
  (cd "$r" && git push -q -u origin add-todo >/dev/null 2>&1)
  github_origin "$r"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 \
    FAKE_GH_PRS="43${TAB}add-todo${TAB}Add todo${TAB}true${TAB}0${TAB}0${TAB}pending${TAB}none"
  check_key "built+pending: change.1.stage" change.1.stage built
  check_key "built+pending: change.1.tasks_done" change.1.tasks_done 3
  check_key "built+pending: pr.1.checks" pr.1.checks pending
  check_key "built+pending: pr.1.draft" pr.1.draft yes
  check_key "built+pending: pr.1.preview_url" pr.1.preview_url none
  check_key "built+pending: pr.1.preview_failed_step" pr.1.preview_failed_step none

  # --- built, no PR -------------------------------------------------------------
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1
  check_key "built, no PR: pr.count" pr.count 0
  check_absent "built, no PR: no pr.1 keys" '^pr\.1\.'
  check_key "built, no PR: change.1.stage" change.1.stage built

  # --- dirty tree split across areas -------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  printf 'export const x = 1\n' >"$r/apps/frontend/src/app.ts"
  printf 'export const y = 2\n' >"$r/packages/lib/src/index.ts"
  printf '# changed\n' >"$r/openspec/specs/app/spec.md"
  printf '# Changed\n' >"$r/README.md"
  printf 'notes\n' >"$r/notes.txt"
  before="$(cd "$r" && git status --porcelain=v1 --untracked-files=all)"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  after="$(cd "$r" && git status --porcelain=v1 --untracked-files=all)"
  check_key "dirty: git.dirty.code" git.dirty.code 2
  check_key "dirty: git.dirty.openspec" git.dirty.openspec 1
  check_key "dirty: git.dirty.other" git.dirty.other 1
  check_key "dirty: git.dirty.untracked" git.dirty.untracked 1
  if [ "$before" = "$after" ]; then pass "dirty: git status unchanged"; else fail "dirty: git status changed"; fi

  # --- main two commits ahead ---------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  printf 'a\n' >"$r/a.txt" && commit_all "$r" one
  printf 'b\n' >"$r/b.txt" && commit_all "$r" two
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "ahead: git.ahead" git.ahead 2
  check_key "ahead: git.ahead_of_origin_main" git.ahead_of_origin_main 2
  check_key "ahead: git.behind_origin_main" git.behind_origin_main 0

  # --- behind origin/main -------------------------------------------------------
  (cd "$r" && git push -q origin main >/dev/null 2>&1 && git reset -q --hard HEAD~1)
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "behind: git.behind" git.behind 1
  check_key "behind: git.behind_origin_main" git.behind_origin_main 1

  # --- two changes, sorted ------------------------------------------------------
  make_repo
  r="$R"
  add_change "$r" beta-change planned
  add_change "$r" alpha-change proposing
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "two changes: change.count" change.count 2
  check_key "two changes: change.1.name" change.1.name alpha-change
  check_key "two changes: change.2.name" change.2.name beta-change
  check_key "two changes: git.fetch without origin" git.fetch skipped
  check_key "two changes: git.upstream" git.upstream none
  check_key "two changes: github.status" github.status no-remote

  # --- remote-only claude/ branch carrying a change (the cloud fresh-chat shape) -
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b claude/todo-9a1)
  add_change "$r" todo-page building
  commit_all "$r" "build todo-page"
  (cd "$r" && git push -q -u origin claude/todo-9a1 >/dev/null 2>&1 && git checkout -q main &&
    git branch -q -D claude/todo-9a1 && git checkout -q -b claude/fresh-0b2)
  probe "$r" ALIGN_PROBE_WIZARD=skip CLAUDE_CODE_REMOTE=true
  check_rc0 "remote-only: exit 0"
  check_key "remote-only: session.kind" session.kind cloud
  check_key "remote-only: wizard.status" wizard.status skipped
  check_key "remote-only: change.count" change.count 0
  check_key "remote-only: branch.count" branch.count 1
  check_key "remote-only: branch.1.kind" branch.1.kind remote
  check_key "remote-only: branch.1.name" branch.1.name claude/todo-9a1
  check_key "remote-only: branch.1.change" branch.1.change todo-page
  check_key "remote-only: branch.1.stage" branch.1.stage building
  check_key "remote-only: branch.1.tasks_done" branch.1.tasks_done 1
  check_key "remote-only: branch.1.tasks_total" branch.1.tasks_total 3
  check_key "remote-only: branch.1.artifacts" branch.1.artifacts discovery,proposal,specs,design,tasks
  check_key "remote-only: branch.1.archived" branch.1.archived no
  check_key "remote-only: branch.1.ahead_of_main" branch.1.ahead_of_main 1
  check_key "remote-only: branch.1.pr" branch.1.pr unavailable
  check_key "remote-only: git.upstream" git.upstream none

  # --- local-only branch carrying a change --------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b claude/todo-9a1)
  add_change "$r" todo-page planned
  commit_all "$r" "plan todo-page"
  (cd "$r" && git checkout -q main)
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "local-only: branch.count" branch.count 1
  check_key "local-only: branch.1.kind" branch.1.kind local
  check_key "local-only: branch.1.name" branch.1.name claude/todo-9a1
  check_key "local-only: branch.1.stage" branch.1.stage planned
  check_key "local-only: branch.1.pr" branch.1.pr unavailable

  # --- pushed branch with a PR seen from main -----------------------------------
  (cd "$r" && git push -q -u origin claude/todo-9a1 >/dev/null 2>&1)
  github_origin "$r"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 \
    FAKE_GH_PRS="7${TAB}claude/todo-9a1${TAB}Todo page${TAB}false${TAB}1${TAB}1${TAB}none${TAB}none"
  check_key "branch+PR: branch.count lists local and remote" branch.count 2
  check_key "branch+PR: branch.1.kind" branch.1.kind local
  check_key "branch+PR: branch.2.kind" branch.2.kind remote
  check_key "branch+PR: branch.1.pr" branch.1.pr 7
  check_key "branch+PR: branch.2.pr" branch.2.pr 7
  check_key "branch+PR: pr.1.change" pr.1.change todo-page
  check_key "branch+PR: pr.1.checks" pr.1.checks none

  # --- archived change excluded; a branch that filed one ------------------------
  make_repo
  r="$R"
  add_origin "$r"
  add_change "$r" 2026-01-01-old built openspec/changes/archive
  commit_all "$r" "old archive"
  (cd "$r" && git push -q origin main >/dev/null 2>&1 && git checkout -q -b feat)
  add_change "$r" 2026-02-02-feat-change built openspec/changes/archive
  commit_all "$r" "file feat-change"
  (cd "$r" && git push -q -u origin feat >/dev/null 2>&1 && git checkout -q main)
  github_origin "$r"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 \
    FAKE_GH_PRS="8${TAB}feat${TAB}Feat${TAB}false${TAB}2${TAB}0${TAB}pass${TAB}https://pr-8.example.workers.dev"
  check_key "archived: change.count" change.count 0
  check_key "archived: branch.count" branch.count 2
  check_key "archived: branch.1.change" branch.1.change feat-change
  check_key "archived: branch.1.archived" branch.1.archived yes
  check_key "archived: branch.1.stage" branch.1.stage built
  check_key "archived: pr.1.change" pr.1.change feat-change
  check_key "archived: pr.1.archived" pr.1.archived yes

  # --- docs/context -------------------------------------------------------------
  make_repo
  r="$R"
  mkdir -p "$r/docs/context"
  printf '# Context\n' >"$r/docs/context/README.md"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "docs/context: README only" repo.docs_context 0
  printf 'a\n' >"$r/docs/context/glossary.md"
  printf 'b\n' >"$r/docs/context/intake-form.md"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "docs/context: two files" repo.docs_context 2
  check_key "docs/context: two unindexed" repo.docs_context_unindexed 2
  printf -- '- glossary.md: the terms of the trade.\n' >>"$r/docs/context/README.md"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "docs/context: one unindexed" repo.docs_context_unindexed 1
  rm "$r/docs/context/README.md"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "docs/context: no README, all unindexed" repo.docs_context_unindexed 2

  # --- replaceme removed --------------------------------------------------------
  printf 'name = "acme";\n' >"$r/flake.nix"
  printf '{ "name": "@acme/root" }\n' >"$r/package.json"
  probe "$r" ALIGN_PROBE_WIZARD=skip
  check_key "personalized: repo.replaceme" repo.replaceme no

  # --- github.status degradations ---------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  github_origin "$r"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 ALIGN_PROBE_NO_GITHUB=1 \
    FAKE_GH_PRS="1${TAB}x${TAB}X${TAB}false${TAB}0${TAB}0${TAB}pass${TAB}none"
  check_key "github disabled: status" github.status disabled
  check_absent "github disabled: no pr.* keys" '^pr\.'
  check_key "github disabled: deploy.main" deploy.main unavailable
  check_absent "github disabled: no deploy.main_days" '^deploy\.main_days'
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_AUTH_RC=1 \
    FAKE_GH_PRS="1${TAB}x${TAB}X${TAB}false${TAB}0${TAB}0${TAB}pass${TAB}none"
  check_key "github unauthenticated: status" github.status unauthenticated
  check_absent "github unauthenticated: no pr.* keys" '^pr\.'
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 "PATH=$TDIR/nogh"
  check_rc0 "github missing: exit 0"
  check_key "github missing: status" github.status missing
  check_absent "github missing: no pr.* keys" '^pr\.'
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PR_RC=1
  check_key "gh pr list fails: status stays ok" github.status ok
  check_key "gh pr list fails: pr.count" pr.count unavailable
  check_absent "gh pr list fails: no pr.1 keys" '^pr\.1\.'

  # --- preview failure drill-down -----------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  (cd "$r" && git checkout -q -b add-todo)
  add_change "$r" add-todo built
  commit_all "$r" "finish add-todo"
  (cd "$r" && git push -q -u origin add-todo >/dev/null 2>&1 && git checkout -q main)
  github_origin "$r"
  local prs="44${TAB}add-todo${TAB}Add todo${TAB}false${TAB}1${TAB}0${TAB}fail${TAB}none"
  log="$TDIR/gh$N.log"
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_LOG="$log" FAKE_GH_PRS="$prs" \
    FAKE_GH_RUN_ID=777 FAKE_GH_FAILED_STEP="Require the preview settings"
  check_key "preview fail: settings" pr.1.preview_failed_step settings
  if grep -q "^run view -R acme/app 777" "$log"; then pass "preview fail: drills into run 777"; else fail "preview fail: run 777 not viewed ($(grep '^run' "$log" | tr '\n' ';'))"; fi
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PRS="$prs" \
    FAKE_GH_RUN_ID=777 FAKE_GH_FAILED_STEP="Wait for the pull request's Supabase branch"
  check_key "preview fail: supabase (wait)" pr.1.preview_failed_step supabase
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PRS="$prs" \
    FAKE_GH_RUN_ID=777 FAKE_GH_FAILED_STEP="Migrate the Supabase branch"
  check_key "preview fail: supabase (migrate)" pr.1.preview_failed_step supabase
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PRS="$prs" \
    FAKE_GH_RUN_ID=777 FAKE_GH_FAILED_STEP="Build"
  check_key "preview fail: other" pr.1.preview_failed_step other
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PRS="$prs" \
    FAKE_GH_RUN_ID=777 FAKE_GH_FAILED_STEP=""
  check_key "preview fail: no failed step" pr.1.preview_failed_step none
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_PRS="$prs" FAKE_GH_RUN_ID=""
  check_key "preview fail: no preview run" pr.1.preview_failed_step none

  # --- deploy -------------------------------------------------------------------
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_DEPLOY="success${TAB}completed${TAB}2"
  check_key "deploy success: deploy.main" deploy.main success
  check_key "deploy success: deploy.main_days" deploy.main_days 2
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_DEPLOY="failure${TAB}completed${TAB}0"
  check_key "deploy failure: deploy.main" deploy.main failure
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1 FAKE_GH_DEPLOY="${TAB}in_progress${TAB}0"
  check_key "deploy running: deploy.main" deploy.main running
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_NO_FETCH=1
  check_key "deploy none: deploy.main" deploy.main none
  check_absent "deploy none: no deploy.main_days" '^deploy\.main_days'

  # --- fetch failure completes --------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  add_change "$r" add-todo planned
  (cd "$r" && git remote set-url origin "$TDIR/does-not-exist")
  probe "$r" ALIGN_PROBE_WIZARD=skip ALIGN_PROBE_TIMEOUT=5
  check_rc0 "fetch fails: exit 0"
  check_key "fetch fails: git.fetch" git.fetch failed
  check_key "fetch fails: change.count still reported" change.count 1
  check_key "fetch fails: github.status" github.status no-remote

  # --- determinism --------------------------------------------------------------
  make_repo
  r="$R"
  add_origin "$r"
  add_change "$r" beta planned
  add_change "$r" alpha building
  probe "$r" ALIGN_PROBE_WIZARD=run
  local first
  first="$(printf '%s\n' "$OUT" | grep -v '^probe.duration_s=')"
  probe "$r" ALIGN_PROBE_WIZARD=run
  if [ "$first" = "$(printf '%s\n' "$OUT" | grep -v '^probe.duration_s=')" ]; then
    pass "determinism: two runs agree"
  else
    fail "determinism: two runs differ"
  fi
}

SAVED_PATH="$PATH"
PATH="$TDIR/fakebin:$SAVED_PATH"
run_suite "host PATH"

if [ -d "$ROOT/.devshell/bin" ]; then
  PATH="$TDIR/fakebin:$ROOT/.devshell/bin:$SAVED_PATH"
  run_suite "pinned toolchain via .devshell"
else
  echo
  echo "  (no .devshell out-link; pinned-toolchain pass skipped)"
fi

echo
echo "  $PASS passed, $FAIL failed"
echo
[ "$FAIL" -eq 0 ]
