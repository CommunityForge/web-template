#!/usr/bin/env bash
# pre-push-check.sh — the push-time gate `flake.nix` registers as the pre-push
# git hook.
#
# Builds only the checks that finish in seconds on a warm cache: formatting,
# spelling and workflow lint. `nix flake check` would also build every package,
# which is CI's job (`check.yml` runs the whole matrix on the pull request) and
# takes longer on one core than a push should ever wait -- long enough that an
# agent's tool call gives up on the push first.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
exec nix build --no-link \
  ".#checks.$system.formatting" \
  ".#checks.$system.spellcheck" \
  ".#checks.$system.actionlint"
