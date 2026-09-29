#!/usr/bin/env bash
# align-probe.sh — read-only facts about where this project stands, as
# `key=value` lines, for the /Align skill to reason with.
#
# Same pattern as the setup wizard's non-interactive run: probe, report,
# mutate nothing. The ONLY thing this script changes is the remote-tracking
# refs `git fetch --prune origin` updates; the working tree is never written.
# Every network step runs under a timeout and has a fallback value, so a run
# finishes in well under a minute with the network gone.
#
# Sentinels: `none` (determined, nothing there), `unknown` (source reachable,
# undecidable), `unavailable` (source not consulted). A section that is
# `unavailable` prints only its status or count key. Booleans are yes|no; ages
# are whole days. Entities are 1-based and sorted (changes by name, branches by
# bare name, pull requests by number) so two runs diff clean.
#
# A change's stage is read the same way wherever it lives: from the working
# tree for `change.N.*`, from a ref's tree (`git ls-tree`, `git show`) for
# `branch.N.*` — never from a checkout. That is what lets a cloud chat, whose
# working tree is a fresh branch, see the stages a laptop sees.
#
# Knobs: ALIGN_PROBE_NO_GITHUB=1 (never call gh), ALIGN_PROBE_NO_FETCH=1,
# ALIGN_PROBE_WIZARD=skip|run (default: run on a macOS desktop only),
# ALIGN_PROBE_TIMEOUT=<seconds> per network step (default 15).
#
# Runs on a GUI-launched client's bare PATH (macOS bash 3.2, BSD userland)
# and prefers the pinned toolchain when the `.devshell` out-link exists. No
# arrays, no `date -d`, no external jq: `gh --jq` does the JSON work.

set -uo pipefail
export LC_ALL=C
if [ -d "$PWD/.devshell/bin" ]; then
  PATH="$PWD/.devshell/bin:$PATH"
fi
# Never block on a credential or host-key prompt.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

START="$(date +%s)"
TIMEOUT="${ALIGN_PROBE_TIMEOUT:-15}"
TAB="$(printf '\t')"
ERRORS=""

emit() { printf '%s=%s\n' "$1" "$2"; }
err() { ERRORS="${ERRORS:+$ERRORS,}$1"; }
yes_no() { if "$@"; then echo yes; else echo no; fi; }

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

# days_since <epoch-seconds>
days_since() {
  local now
  now="$(date +%s)"
  echo $(((now - $1) / 86400))
}

# mtime <path>: GNU stat first (the toolchain), BSD stat second (the host).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s; }

# task_counts: stdin is a tasks.md; prints "<done> <total>".
task_counts() {
  local text checked open
  text="$(cat)"
  checked="$(printf '%s\n' "$text" | grep -cE '^[[:space:]]*- \[[xX]\]')"
  open="$(printf '%s\n' "$text" | grep -cE '^[[:space:]]*- \[ \]')"
  echo "$checked $((checked + open))"
}

# stage_of <artifacts-csv> <done> <total>
stage_of() {
  case ",$1," in
    *,tasks,*)
      if [ "$3" -eq 0 ] || [ "$2" -eq 0 ]; then
        echo planned
      elif [ "$2" -lt "$3" ]; then
        echo building
      else
        echo built
      fi
      ;;
    *) if [ "$1" = none ]; then echo empty; else echo proposing; fi ;;
  esac
}

# artifacts_csv: stdin is the list of entry names in a change folder plus a
# line `specs.md` when its specs/ holds a spec. Prints the artifact names in
# schema order, or `none`.
artifacts_csv() {
  local entries out=""
  entries="$(cat)"
  for pair in discovery:discovery.md proposal:proposal.md specs:specs.md design:design.md tasks:tasks.md; do
    if printf '%s\n' "$entries" | grep -qx "${pair#*:}"; then
      out="${out:+$out,}${pair%%:*}"
    fi
  done
  echo "${out:-none}"
}

# --- where we are --------------------------------------------------------------

emit probe.version 1

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || TOP=""
if [ -z "$TOP" ]; then
  err "not-a-git-repository"
fi
if [ -n "$TOP" ]; then
  cd "$TOP" || err "cd-toplevel"
fi

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  KIND=cloud
elif [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  KIND=desktop-mac
else
  KIND=desktop-linux
fi
emit session.kind "$KIND"
emit session.devshell "$(yes_no test -d .devshell/bin)"

# --- repo ---------------------------------------------------------------------

ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || ORIGIN_URL=""
REPO=none
case "$ORIGIN_URL" in
  *github.com[:/]*)
    REPO="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')"
    printf '%s' "$REPO" | grep -qE '^[^/[:space:]]+/[^/[:space:]]+$' || REPO=none
    ;;
esac
emit repo.github "$REPO"
emit repo.replaceme "$(yes_no grep -qs replaceme package.json flake.nix)"
if [ -d docs/context ]; then
  emit repo.docs_context "$(find docs/context -type f ! -name README.md ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
else
  emit repo.docs_context missing
fi

# --- git ----------------------------------------------------------------------

BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || BRANCH=detached
emit git.branch "$BRANCH"
emit git.on_main "$(yes_no test "$BRANCH" = main)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || UPSTREAM=none
emit git.upstream "$UPSTREAM"

# counts <from> <to>: "<ahead> <behind>" of <from> relative to <to>.
counts() {
  local lr
  lr="$(git rev-list --left-right --count "$1...$2" 2>/dev/null)" || lr="0${TAB}0"
  printf '%s %s\n' "${lr%%"$TAB"*}" "${lr##*"$TAB"}"
}
if [ "$UPSTREAM" != none ]; then
  # shellcheck disable=SC2046 # splitting the pair into positionals is the point
  set -- $(counts HEAD "$UPSTREAM")
else
  set -- 0 0
fi
emit git.ahead "$1"
emit git.behind "$2"

# The fetch happens BEFORE the origin/main comparison and the branch scan, so
# both read what GitHub has now rather than what the last fetch saw.
FETCH=skipped
if [ -z "${ALIGN_PROBE_NO_FETCH:-}" ] && [ -n "$ORIGIN_URL" ]; then
  if with_timeout "$TIMEOUT" git fetch --prune --quiet origin >/dev/null 2>&1; then
    FETCH=ok
  else
    FETCH=failed
  fi
fi

BASE=""
if git rev-parse -q --verify origin/main >/dev/null 2>&1; then
  BASE=origin/main
elif git rev-parse -q --verify main >/dev/null 2>&1; then
  BASE=main
fi
if [ "$BASE" = origin/main ]; then
  # shellcheck disable=SC2046 # splitting the pair into positionals is the point
  set -- $(counts HEAD origin/main)
else
  set -- 0 0
fi
emit git.ahead_of_origin_main "$1"
emit git.behind_origin_main "$2"
emit git.fetch "$FETCH"

DIRTY_OPENSPEC=0
DIRTY_CODE=0
DIRTY_OTHER=0
DIRTY_UNTRACKED=0
STATUS="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)" || err "git-status"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  path="${line#???}"
  path="${path##* -> }"
  case "$line" in
    '??'*) DIRTY_UNTRACKED=$((DIRTY_UNTRACKED + 1)) ;;
    *) case "$path" in
      openspec/*) DIRTY_OPENSPEC=$((DIRTY_OPENSPEC + 1)) ;;
      apps/* | packages/* | supabase/*) DIRTY_CODE=$((DIRTY_CODE + 1)) ;;
      *) DIRTY_OTHER=$((DIRTY_OTHER + 1)) ;;
    esac ;;
  esac
done <<EOS
$STATUS
EOS
emit git.dirty.openspec "$DIRTY_OPENSPEC"
emit git.dirty.code "$DIRTY_CODE"
emit git.dirty.other "$DIRTY_OTHER"
emit git.dirty.untracked "$DIRTY_UNTRACKED"

# --- what every ref carries -----------------------------------------------------
# One `ls-tree` per ref for the active folders and one for the archive, cached
# as "<ref><TAB><name>" lines; everything below reads the cache.

ALL_REFS="$(git for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | grep -vx 'origin/HEAD' | sort)"

# tree_dirs <ref> <path/>: the directory names directly under <path/> in <ref>'s tree.
tree_dirs() {
  git ls-tree -d --name-only "$1" "$2" 2>/dev/null | sed 's#.*/##' | grep -v '^\.' | sort
}

REF_ACTIVE=""
REF_ARCHIVED=""
for ref in $ALL_REFS; do
  for n in $(tree_dirs "$ref" openspec/changes/ | grep -vx archive); do
    REF_ACTIVE="$REF_ACTIVE$ref$TAB$n
"
  done
  for n in $(tree_dirs "$ref" openspec/changes/archive/); do
    REF_ARCHIVED="$REF_ARCHIVED$ref$TAB$n
"
  done
done

# refs_carrying <name>: every ref whose tree has the active folder.
refs_carrying() { printf '%s' "$REF_ACTIVE" | grep -E "$TAB$1\$" | cut -f1 | sort | tr '\n' ',' | sed 's/,$//'; }
# active_on <ref>
active_on() { printf '%s' "$REF_ACTIVE" | grep -E "^$1$TAB" | cut -f2; }
# archived_on <ref>
archived_on() { printf '%s' "$REF_ARCHIVED" | grep -E "^$1$TAB" | cut -f2; }

# ref_facts <ref> <dir>: prints "<artifacts> <done> <total> <stage>" read
# from a folder in a ref's tree.
ref_facts() {
  local entries arts checked total
  entries="$(git ls-tree --name-only "$1" "$2/" 2>/dev/null | sed 's#.*/##')"
  if git ls-tree -r --name-only "$1" "$2/specs/" 2>/dev/null | grep -q '\.md$'; then
    entries="$entries
specs.md"
  fi
  arts="$(printf '%s\n' "$entries" | artifacts_csv)"
  # shellcheck disable=SC2046 # splitting "<done> <total>" into $1 $2 is the point
  set -- $(git show "$1:$2/tasks.md" 2>/dev/null | task_counts)
  checked="$1"
  total="$2"
  printf '%s %s %s %s\n' "$arts" "$checked" "$total" "$(stage_of "$arts" "$checked" "$total")"
}

# --- changes in the working tree -------------------------------------------------

CHANGES=""
if [ -d openspec/changes ]; then
  for d in openspec/changes/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ "$n" = archive ] && continue
    CHANGES="$CHANGES$n
"
  done
fi
CHANGES="$(printf '%s' "$CHANGES" | sort)"
emit change.count "$(printf '%s' "$CHANGES" | grep -c .)"
i=0
for n in $CHANGES; do
  i=$((i + 1))
  d="openspec/changes/$n"
  entries="$(ls -1 "$d" 2>/dev/null)"
  if [ -n "$(find "$d/specs" -name '*.md' 2>/dev/null | head -n1)" ]; then
    entries="$entries
specs.md"
  fi
  arts="$(printf '%s\n' "$entries" | artifacts_csv)"
  if [ -f "$d/tasks.md" ]; then
    # shellcheck disable=SC2046 # splitting the pair into positionals is the point
    set -- $(task_counts <"$d/tasks.md")
  else
    set -- 0 0
  fi
  emit "change.$i.name" "$n"
  emit "change.$i.stage" "$(stage_of "$arts" "$1" "$2")"
  emit "change.$i.tasks_done" "$1"
  emit "change.$i.tasks_total" "$2"
  emit "change.$i.artifacts" "$arts"
  ts="$(git log -1 --format=%ct -- "$d" 2>/dev/null)"
  [ -n "$ts" ] || ts="$(mtime "$d")"
  emit "change.$i.age_days" "$(days_since "$ts")"
  carrying="$(refs_carrying "$n")"
  emit "change.$i.branches" "${carrying:-none}"
done

# --- GitHub ---------------------------------------------------------------------
# Computed before the branch section so each branch can name its pull request.

GH=ok
if [ -n "${ALIGN_PROBE_NO_GITHUB:-}" ]; then
  GH=disabled
elif [ "$REPO" = none ]; then
  GH=no-remote
elif ! command -v gh >/dev/null 2>&1; then
  GH=missing
elif ! with_timeout "$TIMEOUT" gh auth status -h github.com >/dev/null 2>&1; then
  GH=unauthenticated
fi

# shellcheck disable=SC2016 # jq's own $c, not a shell variable
PR_JQ='
def checks:
  (.statusCheckRollup // []) as $c
  | if ($c | length) == 0 then "none"
    else ($c | map(
        if .__typename == "CheckRun" then
          (if .status != "COMPLETED" then "pending"
           elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "pass"
           else "fail" end)
        else
          (if .state == "SUCCESS" then "pass"
           elif (.state == "PENDING" or .state == "EXPECTED") then "pending"
           else "fail" end)
        end)
      | if any(. == "fail") then "fail" elif any(. == "pending") then "pending" else "pass" end)
    end;
def preview:
  ([.comments[]? | select(.body | startswith("## Preview"))] | last) as $c
  | if $c == null then "none"
    else (($c.body | split("\n") | map(select(startswith("https://"))) | first) // "none") end;
def days(f): ((now - (f | fromdateiso8601)) / 86400 | floor);
.[] | [.number, .headRefName, .title, (.isDraft | tostring), days(.createdAt), days(.updatedAt), checks, preview] | @tsv
'

PR_TSV=""
PR_STATE=none
if [ "$GH" = ok ]; then
  if PR_TSV="$(with_timeout "$TIMEOUT" gh pr list -R "$REPO" --state open --base main --limit 50 \
    --json number,headRefName,title,isDraft,createdAt,updatedAt,statusCheckRollup,comments \
    --jq "$PR_JQ" 2>/dev/null)"; then
    PR_STATE=ok
    PR_TSV="$(printf '%s\n' "$PR_TSV" | grep . | sort -n -t "$TAB" -k1,1)"
  else
    PR_STATE=unavailable
    PR_TSV=""
  fi
fi

# pr_for_branch <bare-name>: the open pull request's number, `none`, or `unavailable`.
pr_for_branch() {
  local num
  [ "$PR_STATE" = ok ] || {
    echo unavailable
    return
  }
  num="$(printf '%s\n' "$PR_TSV" | cut -f1,2 | while IFS="$TAB" read -r number head; do
    if [ "$head" = "$1" ]; then
      echo "$number"
      break
    fi
  done)"
  echo "${num:-none}"
}

# --- other branches carrying a change ----------------------------------------------
# Every local or remote branch not merged into the base, minus the current
# branch and its upstream (the working tree already shows those), one entry per
# (branch, change) so every key stays single-valued.

if [ -n "$BASE" ]; then
  OTHER_REFS="$(git for-each-ref --format='%(refname:short)' --no-merged="$BASE" refs/heads/ refs/remotes/origin/ 2>/dev/null)"
else
  OTHER_REFS="$ALL_REFS"
fi
BASE_ARCHIVED=""
[ -n "$BASE" ] && BASE_ARCHIVED="$(archived_on "$BASE")"

ENTRIES=""
for ref in $OTHER_REFS; do
  [ "$ref" = origin/HEAD ] && continue
  [ "$ref" = "$BRANCH" ] && continue
  [ "$ref" = "$UPSTREAM" ] && continue
  case "$ref" in
    origin/*)
      kind=1
      bare="${ref#origin/}"
      ;;
    *)
      kind=0
      bare="$ref"
      ;;
  esac
  active="$(active_on "$ref")"
  for n in $active; do
    ENTRIES="$ENTRIES$bare$TAB$kind$TAB$ref$TAB$n${TAB}openspec/changes/$n${TAB}no
"
  done
  for a in $(archived_on "$ref"); do
    printf '%s\n' "$BASE_ARCHIVED" | grep -qx "$a" && continue
    n="$(printf '%s' "$a" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')"
    printf '%s\n' "$active" | grep -qx "$n" && continue
    ENTRIES="$ENTRIES$bare$TAB$kind$TAB$ref$TAB$n${TAB}openspec/changes/archive/$a${TAB}yes
"
  done
done
ENTRIES="$(printf '%s' "$ENTRIES" | sort)"
emit branch.count "$(printf '%s' "$ENTRIES" | grep -c .)"
i=0
while IFS="$TAB" read -r bare kind ref n dir archived; do
  [ -n "$bare" ] || continue
  i=$((i + 1))
  # shellcheck disable=SC2046 # splitting the pair into positionals is the point
  set -- $(ref_facts "$ref" "$dir")
  emit "branch.$i.kind" "$([ "$kind" = 1 ] && echo remote || echo local)"
  emit "branch.$i.name" "$bare"
  emit "branch.$i.change" "$n"
  if [ -n "$BASE" ]; then
    emit "branch.$i.ahead_of_main" "$(git rev-list --count "$BASE..$ref" 2>/dev/null || echo 0)"
  else
    emit "branch.$i.ahead_of_main" 0
  fi
  emit "branch.$i.pr" "$(pr_for_branch "$bare")"
  emit "branch.$i.stage" "$4"
  emit "branch.$i.tasks_done" "$2"
  emit "branch.$i.tasks_total" "$3"
  emit "branch.$i.artifacts" "$1"
  emit "branch.$i.archived" "$archived"
done <<EOS
$ENTRIES
EOS

# --- pull requests -----------------------------------------------------------------

emit github.status "$GH"
if [ "$GH" = ok ]; then
  if [ "$PR_STATE" = ok ]; then
    emit pr.count "$(printf '%s' "$PR_TSV" | grep -c .)"
    i=0
    drills=0
    while IFS="$TAB" read -r number head title draft age updated checks preview; do
      [ -n "$number" ] || continue
      i=$((i + 1))
      emit "pr.$i.number" "$number"
      emit "pr.$i.branch" "$head"
      change=unknown
      archived=unknown
      if printf '%s\n' "$ALL_REFS" | grep -qx "origin/$head"; then
        change="$(active_on "origin/$head" | head -n1)"
        archived=no
        if [ -z "$change" ]; then
          for a in $(archived_on "origin/$head"); do
            printf '%s\n' "$BASE_ARCHIVED" | grep -qx "$a" && continue
            change="$(printf '%s' "$a" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')"
            archived=yes
            break
          done
        fi
        [ -n "$change" ] || change=none
      fi
      emit "pr.$i.change" "$change"
      emit "pr.$i.title" "$title"
      emit "pr.$i.draft" "$([ "$draft" = true ] && echo yes || echo no)"
      emit "pr.$i.age_days" "$age"
      emit "pr.$i.updated_days" "$updated"
      emit "pr.$i.checks" "$checks"
      emit "pr.$i.preview_url" "$preview"
      step=none
      if [ "$checks" = fail ] && [ "$drills" -lt 5 ]; then
        drills=$((drills + 1))
        if run_id="$(with_timeout "$TIMEOUT" gh run list -R "$REPO" --workflow preview.yml --branch "$head" --limit 1 \
          --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null)"; then
          run_id="$(printf '%s' "$run_id" | tr -d '[:space:]')"
          if [ -n "$run_id" ]; then
            if name="$(with_timeout "$TIMEOUT" gh run view -R "$REPO" "$run_id" --json jobs \
              --jq '[.jobs[]?.steps[]? | select(.conclusion == "failure") | .name] | first // empty' 2>/dev/null)"; then
              case "$name" in
                "") step=none ;;
                "Require the preview settings") step=settings ;;
                "Wait for"* | "Look up"* | "Migrate the Supabase branch") step=supabase ;;
                *) step=other ;;
              esac
            else
              step=unknown
            fi
          fi
        else
          step=unknown
        fi
      fi
      emit "pr.$i.preview_failed_step" "$step"
      emit "pr.$i.archived" "$archived"
    done <<EOS
$PR_TSV
EOS
  else
    emit pr.count unavailable
  fi
fi

# --- deploy ---------------------------------------------------------------------------

if [ "$GH" = ok ]; then
  if line="$(with_timeout "$TIMEOUT" gh run list -R "$REPO" --workflow deploy.yml --branch main --limit 1 \
    --json conclusion,status,updatedAt \
    --jq '.[0] | select(. != null) | [(.conclusion // ""), .status, ((now - (.updatedAt | fromdateiso8601)) / 86400 | floor)] | @tsv' 2>/dev/null)"; then
    line="$(printf '%s\n' "$line" | grep . | head -n1)"
    if [ -z "$line" ]; then
      emit deploy.main none
    else
      IFS="$TAB" read -r conclusion status days <<EOS
$line
EOS
      if [ "$status" != completed ]; then
        emit deploy.main running
      elif [ "$conclusion" = success ]; then
        emit deploy.main success
      else
        emit deploy.main failure
      fi
      emit deploy.main_days "${days:-0}"
    fi
  else
    emit deploy.main unavailable
  fi
else
  emit deploy.main unavailable
fi

# --- wizard ---------------------------------------------------------------------------
# The macOS wizard doubles as a readiness probe when stdin is not a terminal:
# every mutation is skipped and the closing list names what is still to do.

WIZ="${ALIGN_PROBE_WIZARD:-}"
if [ -z "$WIZ" ]; then
  if [ "$KIND" = desktop-mac ]; then WIZ=run; else WIZ=skip; fi
fi
if [ "$WIZ" != run ]; then
  emit wizard.status skipped
elif [ ! -f Setup.command ]; then
  emit wizard.status absent
else
  out="$(with_timeout 45 bash Setup.command </dev/null 2>&1)"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then
    emit wizard.status timeout
  elif printf '%s' "$out" | grep -q 'Setup complete'; then
    emit wizard.status ok
  else
    emit wizard.status stopped-early
  fi
  todos="$(printf '%s\n' "$out" | sed -n '/still to do by hand:/,$p' | sed -n 's/^    - //p')"
  emit wizard.todo.count "$(printf '%s' "$todos" | grep -c .)"
  i=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    i=$((i + 1))
    emit "wizard.todo.$i" "$t"
  done <<EOS
$todos
EOS
fi

emit probe.errors "${ERRORS:-none}"
emit probe.duration_s "$(($(date +%s) - START))"
exit 0
