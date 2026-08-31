# Community Forge Web Template

> [!WARNING]
> This project is a work-in-progress.
> Breaking changes will be frequent.
> Public-facing documentation, including installation instructions, is incomplete.

A minimal, app-agnostic pnpm + TypeScript + Effect monorepo with reproducible Nix builds.
Structure follows [Effect](https://github.com/Effect-TS/effect)'s conventions; the Nix layer
follows SolidChess's. Everything domain-specific has been stripped — `packages/core` is a
placeholder to be deleted once real modules land, and `apps/frontend` is a Vite + React 19 + Tailwind 4
SPA shell.

The npm scope is the literal placeholder `@replaceme`. Renaming on fork takes two steps.

First the scope (`sed -i ''` is BSD/macOS; on GNU sed drop the `''`):

```sh
grep -rl '@replaceme' --exclude-dir={node_modules,.git,.direnv,dist,.repos} . \
  | xargs sed -i '' 's|@replaceme|@yourscope|g'
```

Then `projectName` in `flake.nix`, which names the `toolchain` and `devShell` derivations.
A bare `replaceme` search-and-replace will not do: it also matches inside the word
"replacement", which appears in several vendored skill documents.

## Getting a shell

Every command assumes the Nix dev shell, which supplies Node, pnpm, oxlint, oxfmt, tsgolint and
typos — there is no `packageManager` field and no `.nvmrc`.

The only host prerequisite is Nix itself, installed with a daemon (the standard multi-user
installer — the tracked sandbox config in `.claude/settings.json` talks to the daemon socket).
From there, install Nix, clone, and point Claude Code at the repo root; an agent bootstraps
through `nix develop -c` on its own. The steps below are the same bootstrap for a human:

```sh
git submodule update --init --recursive # reference checkouts under .repos/, for agents
direnv allow                            # or: nix develop
pnpm install
```

`.repos/` holds shallow read-only checkouts that coding agents consult as prior art. Nothing
in the build depends on them; skip the submodule step if you do not need them.

| Command            | What it does                                      |
| ------------------ | ------------------------------------------------- |
| `pnpm check`       | Type-checks the whole graph, sources and tests    |
| `pnpm test`        | Vitest across all workspace units                 |
| `pnpm lint`        | oxlint                                            |
| `pnpm build`       | Builds every unit's `dist/`                       |
| `nix fmt`          | treefmt — nix, shell, TS/JS, Markdown, YAML, JSON |
| `nix flake check`  | Formatting and spellcheck                         |
| `nix build .#core` | Reproducible build of one unit                    |

## Where the details live

`AGENTS.md` is the reference for how this repo is put together — layout, the conventions that are
load-bearing, adding a package or an app, the Nix build model, and the Effect wiring. It is written
for both humans and coding agents; read it before changing anything structural.

`apps/frontend/AGENTS.md` covers that app specifically.

## License

Not yet chosen. Until a `LICENSE` file lands, no rights are granted — the code is readable
here but not licensed for reuse, and `packages/core` is marked `private` so it cannot be
published by accident.
