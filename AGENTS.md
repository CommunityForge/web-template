# Monorepo root

A pnpm + TypeScript + Effect monorepo with reproducible Nix builds. This file is the reference
for the whole repo; `README.md` is a short human-facing intro and does not repeat any of it.

Per-unit addenda live in `apps/<name>/AGENTS.md` and record only what is specific to that unit.
Where a unit's file and this one disagree, the unit's file wins inside that unit.

**Doc convention**: `AGENTS.md` holds the content. `CLAUDE.md` beside it is a one-line
`@AGENTS.md` import and must stay that way — never write content into a `CLAUDE.md`.

## Learning more about Effect

This repository uses the Effect TypeScript library.

Before writing any Effect code, first read `node_modules/effect/AGENTS.md` **completely**, and
follow the links in the file when required.

If you need to learn more about particular Effect apis and concepts that the guide doesn't cover,
search through the source code in `node_modules/effect/src`.

`effect` is a root dev dependency (`catalog:effect`) only so those two paths resolve from the repo
root; every workspace unit declares its own dependency as well.

## Commands

All of these assume the dev shell (`direnv allow`, or `nix develop -c <cmd>`). Node, pnpm, oxlint,
oxfmt, tsgolint and typos all come from Nix rather than npm, so there is one source of truth for
tool versions and no native postinstall to run inside the build sandbox. Consequently there is no
`packageManager` field and no `.nvmrc`.

| Command              | What it does                                                             |
| -------------------- | ------------------------------------------------------------------------ |
| `pnpm check`         | `tsc -b tsconfig.json` — type-checks the whole graph, sources and tests  |
| `pnpm build`         | Builds every unit's `dist/` (`tsc -b`, then Babel for `/*#__PURE__*/`)   |
| `pnpm test`          | Vitest across all workspace units                                        |
| `pnpm coverage`      | Same, with v8 coverage                                                   |
| `pnpm lint`          | oxlint, including the type-aware tsgolint pass                           |
| `pnpm clean`         | Removes `dist/`, `coverage/`, `*.tsbuildinfo`                            |
| `nix fmt`            | treefmt — see "Formatting" below for what it actually covers             |
| `nix flake check`    | `formatting`, `spellcheck` (typos)                                       |
| `nix build .#<unit>` | Reproducible build of one unit; its `checkPhase` re-runs check/test/lint |

`pnpm lint` already passes `--type-aware`, so the tsgolint rules run locally. The per-unit
`nix build` runs the same pass inside its `checkPhase`, which is what gates a release build.

### Formatting

`nix fmt` is treefmt over nixfmt, shfmt, shellcheck and oxfmt. oxfmt is not JS/TS-only — its
treefmt module claims `*.md`, `*.yaml`, `*.json`, `*.jsonc`, `*.css` and `*.html` as well, so
Markdown and YAML in this repo are formatted, not free-form. Do not hand-wrap Markdown; let
`nix fmt` do it. `.oxfmtrc.json` holds the style and is shared with the editor.

## Layout

```
tsconfig.base.json       All compilerOptions. `include: []` — never built directly.
tsconfig.packages.json   Build graph: references → packages/*
tsconfig.apps.json       Build graph: references → apps/*   (empty; see below)
tsconfig.json            Solution file: references the three above
tsconfig.tests.json      Test graph: noEmit, `paths` → source
vitest.config.ts         `test.projects` globs; keeps a bare `vitest` from sweeping the repo
vitest.shared.ts         Shared base every unit merges via `mergeConfig`
nix/buildPnpmPackage.nix pnpm-workspace-aware wrapper around buildNpmPackage
<unit>/<name>.nix        One flake-parts module per unit, colocated
```

`tsconfig.base.json` uses `${configDir}` templating, which is why every leaf tsconfig is six lines
with no path overrides.

`tsconfig.apps.json`'s `references` array is empty **on purpose**: `apps/frontend` is a
bundler-built leaf, not a composite project. See `apps/frontend/AGENTS.md`.

## Repo-wide rules

- **Every dependency resolves through `catalog:`, `catalog:effect`, or `workspace:` — never a
  literal version.** This is the one rule that keeps the tree coherent as the repo grows, and it
  is what makes `pnpm add <pkg>` the wrong command: edit the manifest and the catalog in
  `pnpm-workspace.yaml`, then install. The named `effect` catalog exists so the whole Effect line
  moves in lockstep.
- **Never add `eslint`, `eslint-config-next`, or typescript-eslint.** The repo runs
  `typescript@7` (Effect's tsgo build) and typescript-eslint hard-refuses to load against it. The
  type-aware pass uses tsgolint, which reads types through the same Go compiler.
- **oxlint's `correctness`, `suspicious` and `perf` categories are all `error`.** Notable
  consequences: `typescript/array-type` is `generic` (`Array<T>`, not `T[]`),
  `typescript/consistent-type-imports` wants inline `type` specifiers, and `eslint/no-console` is
  an error outside `**/test/**` and `**/scripts/**`.
- **`typescript/no-namespace`, `typescript/no-explicit-any`, `eslint/require-yield`,
  `eslint/no-fallthrough` and `eslint/no-await-in-loop` are off** — they fight Effect idioms.
  `no-explicit-any` being off is not permission to use `any`: casts and `any` are avoided by
  convention, and a rule disabled for generator/namespace ergonomics is not an exemption.
- **`.oxlintrc.json` lives only at the root**, and oxlint resolves `overrides.files` globs relative
  to the config file's directory. Per-unit `.nix` files therefore pull `../../.oxlintrc.json` into
  the build sandbox. All lint lanes pass `--disable-nested-config` so oxlint does not discover
  `.repos/effect/.oxlintrc.json`, which declares an uninstalled JS plugin.
- **British spellings fail `nix flake check`.** `typos` runs with `default.locale = "en-us"` over
  everything except `.repos/`, `pnpm-lock.yaml` and `flake.lock`.

## Tests

Every unit merges `vitest.shared.ts`, so these hold everywhere:

- **`sequence.concurrent` is on**, so tests within a file run at the same time.
- **`globals` is not set**, so libraries that rely on implicit global hooks do not get them —
  `@testing-library/react` never registers its automatic `afterEach(cleanup)`, for one.
- Collection is `test/**/*.test.ts` per unit. `exclude` **replaces** Vitest's default list rather
  than extending it, which is why `**/node_modules/**` and `**/dist/**` are restated there.
- `vitest.setup.ts` runs for every project and calls `addEqualityTesters()`.
- Tests import `describe`/`it` from `@effect/vitest`, not from `vitest`.

`tsconfig.tests.json` globs `packages/*/test/**/*.ts` and `apps/*/test/**/*.ts`. Its `paths` block
resolves every workspace package regardless of declared dependencies — deliberately, as the escape
hatch for `internal/*` and cyclic test dependencies. The cost is that `pnpm check` will not catch a
test importing a package its unit does not depend on. Vitest will.

## Adding a package

1. Copy `packages/core` to `packages/<name>` and rename it in `package.json` and `<name>.nix`.
2. Add `{ "path": "packages/<name>" }` to `tsconfig.packages.json`.
3. Add `./packages/<name>/<name>.nix` to `imports` in `flake.nix`.
4. If it has tests importing other workspace packages, add its `paths` entries to
   `tsconfig.tests.json`.

That is the whole checklist — `pnpm-workspace.yaml` and `vitest.config.ts` glob `packages/*`
already. Verified by copying `packages/core` and confirming only steps 2 and 3 touch anything
outside the new directory.

`packages/core` is a placeholder holding one `Greeting.ts`, to be deleted once real modules land.

### Project references are not optional

A unit's `tsconfig.json` must declare `references` mirroring its `workspace:` dependencies. Package
`exports` point at source (`./src/index.ts`), so without a reference TypeScript pulls the
dependency's `.ts` files in as inputs of _your_ project — losing build ordering, ignoring the
dependency's own compilerOptions, and violating `rootDir`. With the reference, the
source-of-project-reference redirect makes it consume `dist/*.d.ts` and `tsc -b` builds the
dependency first. Confirm which happened by grepping the consumer's `tsconfig.tsbuildinfo` for the
dependency: `dist/*.d.ts` is correct, `src/*.ts` is not.

## Adding an app

For a bundler-built frontend (Vite/React), the app is a **leaf, not a project reference**: set
`composite: false`, `declaration: false`, `noEmit: true`, `moduleResolution: "bundler"`,
`rootDir: null`, `include: ["src", "vite.config.ts"]`, and build with `vite build`. The bundler
resolves workspace dependencies itself, so leave it out of `tsconfig.apps.json`'s `references`.
`apps/frontend` is the worked example.

For a `tsc`-emitting Node app, treat it exactly like a package and add it to `tsconfig.apps.json`.
Be aware that `pnpm deploy` does **not** apply `publishConfig`, so a deployed app's copy of a
workspace dependency keeps its source-first `exports` and will fail at runtime with
`ERR_MODULE_NOT_FOUND`. Bundle the app, or rewrite the manifests on the way out.

## Nix builds

Each unit's `<name>.nix` declares its own dependency closure twice: `pnpmWorkspaces` (which
workspace projects to fetch) and `extraSrcs` (which files to expose). `buildPnpmPackage` narrows
`pnpm-workspace.yaml` to just those projects before fetching, so a unit's fixed-output hash depends
only on its own closure rather than the whole repo's.

`extraSrcs` lists files explicitly rather than passing a bare directory: a bare directory sweeps
`node_modules/` and a stale `dist/` into the sandbox, which would silently satisfy `tsc -b`
incrementality.

**Changing dependencies changes the hash.** Set `hash = pkgs.lib.fakeHash;`, run the build, and
paste the reported hash back in. A stale hash surfaces as `ERR_PNPM_NO_OFFLINE_TARBALL` from inside
the build; `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` instead means `pnpm-lock.yaml` is out of sync with
`pnpm-workspace.yaml`'s catalogs and needs a plain `pnpm install` first.

Working directory inside the derivation mirrors the repo root, so a package at `packages/core`
builds into `./packages/core/dist`.

`prepare` runs `effect-tsgo patch`, which patches the TypeScript binary so the Effect
language-service plugin contributes diagnostics. Nix builds install with `--ignore-scripts`, so
`prepare` never runs there and `nix build` type-checks with unpatched `typescript`. `pnpm check`
locally is therefore slightly stricter than the sandbox. Add
`preBuild = "pnpm exec effect-tsgo patch";` to a unit's `.nix` if you want parity — the patch is
purely local file manipulation and is sandbox-safe.

## Agent configuration

The dev shell's `shellHook` exports `CLAUDE_CONFIG_DIR="$PWD/.claude"` when entered from the
repo root, so Claude Code started from a `nix develop` or `direnv` shell keeps its config and
session state inside the repo. Desktop and IDE clients ignore this and use `~/.claude`, so
`./.claude` is only the live config directory for terminal sessions.

There is no custom sandbox wrapper. Claude Code's own sandbox — configured in
`.claude/settings.json`, see the next section — is the only one, which is why that file is
tracked.

Because `./.claude` can be `CLAUDE_CONFIG_DIR`, it mixes tracked project config with runtime
state. `.gitignore` ignores `.claude/*` and re-includes only `settings.json`, `hooks/`, `commands/`,
`agents/` and `skills/`, so credentials and session history stay out of git while a clone still
gets the workflow boundary. Add a re-include when you add a new config directory there.

## Agents in a sandboxed client

Desktop and IDE clients run Bash tool calls inside a seatbelt sandbox that, by default, blocks
three things this repo needs: the nix daemon socket, writes under the nix cache, and all network
egress. `.claude/settings.json`'s `sandbox` block grants exactly those, which is what lets an agent
run `nix develop -c pnpm install` in a fresh clone with no terminal step. Egress stays
deny-by-default outside the listed domains.

The alternative for anyone who would rather not widen the sandbox: `nix build .#toolchain
--out-link .devshell` produces `./.devshell/bin`, a stable PATH entry holding the whole toolchain
that survives flake bumps. Reads under `/nix/store` are already permitted, so an agent can use it
without reaching the daemon at all. `nix-direnv`'s cached `.direnv/flake-profile` is the same
environment as JSON if the out-link is absent.

## Workflow tooling

OpenSpec and Superpowers are both installed, and the boundary between them is settled and
enforced — the next section is the reference, and `.claude/hooks/boundary-guard.sh` is what
actually blocks a violation. Still do not open an OpenSpec change unless asked to.

<!-- BEGIN openspec-boundary -->

## Workflow boundary: OpenSpec owns this project

**This section is context, not the enforcement mechanism.** The boundary is
enforced by a PreToolUse hook at `.claude/hooks/boundary-guard.sh`, which
blocks the tool call outright. This text exists so you understand _why_
before you hit a denial — a rule you understand is one you don't trip over.

### The situation

OpenSpec and Superpowers both define a complete idea-to-code chain, and they
overlap exactly: both produce a design document, both produce a task list,
both want to drive execution. Running both chains yields two sources of
truth, and only OpenSpec's get synced into living specs and archived.

So: OpenSpec is the workflow. Superpowers is a library you borrow from.

### What the hook blocks, and why

| Blocked                                                           | Reason                                                        |
| ----------------------------------------------------------------- | ------------------------------------------------------------- |
| Writes to `docs/superpowers/plans/` or `docs/superpowers/specs/`  | Duplicate artifacts OpenSpec never syncs or archives          |
| `writing-plans`, `executing-plans`, `subagent-driven-development` | Second orchestrator; the expensive execution path             |
| `REQUIRED SUB-SKILL` text inside `openspec/changes/` files        | Makes an artifact re-arm the sub-agent path in later sessions |

If you are blocked, the denial message names the correct alternative. Follow
it rather than looking for a way around.

### Where the chain gets cut

The `brainstorming` skill's checklist ends with a user review gate on the
written spec, then transitions to `writing-plans`. **Stop at the review
gate.** Tell the user:

> Design approved. Run `/opsx:continue` to generate the OpenSpec artifacts.

Attempting the transition will be blocked by the hook, so stopping
voluntarily is simply faster.

### Superpowers skills that ARE welcome

Invoke these when the user asks, by name or intent:

- `brainstorming` — before `/opsx:propose` or `/opsx:continue`
- `test-driven-development` — during `/opsx:apply`
- `systematic-debugging` — when stuck on a defect
- `requesting-code-review` — before `/opsx:archive`

Each is a self-contained discipline that produces no competing artifact.

### Artifact locations

- design → `openspec/changes/<change-name>/design.md`
- plan → `openspec/changes/<change-name>/tasks.md`

### Two operational notes

`brainstorming` has a hard gate blocking implementation until a design is
approved. During `/opsx:apply` that gate is already satisfied — the design
was approved and written. Do not re-trigger it mid-apply.

Before `/opsx:apply`, ask the user to clear context. Everything needed is on
disk, and a large planning transcript is the main cause of slow apply runs.
<!-- END openspec-boundary -->
