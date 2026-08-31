#!/usr/bin/env bash
# boundary-check.sh — audit for things the hook cannot catch.
#
# The hook prevents leaks going forward. This finds leaks that predate the
# install, arrived via git merge, or were written by another tool entirely.
# It also checks quality signals the hook has no opinion about.
#
# Exit 0 = clean, 1 = problems found.

set -uo pipefail
export LC_ALL=C
if [ -d "$PWD/.devshell/bin" ]; then
  PATH="$PWD/.devshell/bin:$PATH"
fi

FAIL=0
ok() { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
bad() {
  printf '  \033[31mBAD\033[0m   %s\n' "$1"
  FAIL=1
}

echo
echo "Boundary audit"
echo "--------------"

[ -d openspec ] || {
  echo "  No openspec/ directory. Run 'openspec init' first."
  exit 1
}

# --- 1. Is the enforcement actually wired up? -------------------------------
if [ -x .claude/hooks/boundary-guard.sh ]; then
  ok "guard hook present and executable"
else
  bad "guard hook missing — enforcement is OFF; re-run install.sh"
fi

if grep -q "boundary-guard" .claude/settings.json 2>/dev/null; then
  ok "hook registered in .claude/settings.json"
else
  bad "hook NOT registered — it will never fire; re-run install.sh"
fi

if [ -x bin/test-hooks.sh ] && [ -x .claude/hooks/boundary-guard.sh ]; then
  if bash bin/test-hooks.sh .claude/hooks/boundary-guard.sh >/dev/null 2>&1; then
    ok "guard passes its own test suite"
  else
    bad "guard FAILS its test suite — run: bin/test-hooks.sh .claude/hooks/boundary-guard.sh"
  fi
fi

if [ -f openspec/config.yaml ]; then
  ok "openspec/config.yaml present"
else
  bad "openspec/config.yaml missing"
fi

# --- 2. Pre-existing leaks the hook never saw -------------------------------
for d in docs/superpowers/plans docs/superpowers/specs; do
  if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
    bad "$d/ has files — predates the hook, or arrived via merge"
    find "$d" -mindepth 1 -maxdepth 1 -exec printf '          %s\n' {} +
    echo "          -> fold into openspec/changes/<name>/ then delete"
  fi
done
[ "$FAIL" -eq 1 ] || ok "no stray planning artifacts"

HITS=$(grep -rl "REQUIRED SUB-SKILL" openspec/changes 2>/dev/null || true)
if [ -n "$HITS" ]; then
  bad "artifacts carry executor directives"
  while IFS= read -r hit; do printf '          %s\n' "$hit"; done <<<"$HITS"
else
  ok "no executor directives in artifacts"
fi

# --- 3. Things no hook can judge --------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  WT=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$WT" -gt 1 ]; then
    warn "$WT worktrees — openspec/changes/ can diverge between them"
  else
    ok "single worktree"
  fi
fi

for d in openspec/changes/*/; do
  [ -d "$d" ] || continue
  case "$d" in *archive*) continue ;; esac
  name=$(basename "$d")
  if [ -f "$d/discovery.md" ]; then
    ok "$name: discovery.md present"
  elif [ -f "$d/proposal.md" ]; then
    if grep -qi "## Clarifications" "$d/proposal.md"; then
      n=$(grep -ci '^### Q' "$d/proposal.md" 2>/dev/null || echo 0)
      if [ "$n" -ge 3 ]; then
        ok "$name: $n clarifications recorded"
      else warn "$name: only $n clarifications — was elicitation thin?"; fi
    else
      warn "$name: no Clarifications section — nothing was asked"
    fi
  fi
done

echo
[ "$FAIL" -eq 0 ] && echo "Clean." || echo "Problems found. See above."
exit "$FAIL"
