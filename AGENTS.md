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

| Command                     | What it does                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `pnpm check`                | `tsc -b tsconfig.json` — type-checks the whole graph, sources and tests  |
| `pnpm build`                | Builds every unit's `dist/` (`tsc -b`, then Babel for `/*#__PURE__*/`)   |
| `pnpm test`                 | Vitest across all workspace units                                        |
| `pnpm test:types`           | tstyche type tests (`test/**/*.tst.ts`) in every unit that has them      |
| `pnpm coverage`             | Same, with v8 coverage                                                   |
| `pnpm lint`                 | oxlint, including the type-aware tsgolint pass                           |
| `pnpm clean`                | Removes `dist/`, `coverage/`, `*.tsbuildinfo`                            |
| `nix fmt`                   | treefmt — see "Formatting" below for what it actually covers             |
| `nix flake check`           | `formatting`, `spellcheck` (typos)                                       |
| `nix build .#<unit>`        | Reproducible build of one unit; its `checkPhase` re-runs check/test/lint |
| `nix build .#server-worker` | The deployable Worker: `worker.js` beside the frontend's `assets/`       |

### Formatting

`tsx` is a root dev dependency so `src/bin/*.ts` entry points (`packages/db/src/bin/migrate.ts`, `apps/server`'s dev
launcher) run without a build: `pnpm exec tsx <file>`.

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
supabase/                Supabase CLI project: `config.toml`, `seed.sql` (auth.* only; DDL is packages/db's)
```

The units, each with an `AGENTS.md` recording only what is specific to it:

| Unit                | Is                                                                                                                |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `packages/lib`      | The copy source for a new package: one module, one test, the unit `.nix` shape                                    |
| `packages/domain`   | The contracts a client and the server agree on; depends on `effect` alone                                         |
| `packages/db`       | Postgres client, DDL, exposure audit, repositories, and the tstyche drift gate                                    |
| `packages/supabase` | Effect bindings for `supabase-js`: client, `Auth` adapter, claim decoding                                         |
| `apps/frontend`     | Vite + React SPA, a bundler-built leaf                                                                            |
| `apps/server`       | The HTTP API implementing `domain`: a `tsc`-emitting Node app and the Cloudflare Worker serving the SPA beside it |

`tsconfig.base.json` uses `${configDir}` templating, which is why every leaf tsconfig is six lines
with no path overrides.

`tsconfig.apps.json`'s `references` array is empty **on purpose**: `apps/frontend` is a
bundler-built leaf, not a composite project. See `apps/frontend/AGENTS.md`.

## Repo-wide rules

- **Every dependency shared across units resolves through `catalog:`, `catalog:effect`, or
  `workspace:`; unit-local dependencies may pin ordinary ranges** (the frontend's React stack and
  the root's Babel toolchain do). The catalogs are what keep the shared tree coherent as the repo
  grows, and they make `pnpm add <pkg>` the wrong command: edit the manifest — and the catalog in
  `pnpm-workspace.yaml` for a shared dependency — then install. The named `effect` catalog pins the
  whole Effect line to one release so it moves in lockstep; bump every entry together, and keep
  `@effect/vitest`'s vitest peer range satisfied by the `vitest` catalog entry.
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

## Import style

**Every import binds a namespace: `import * as Name from "specifier"`.** `Name` is PascalCase
derived from the module, not from what it exports — `@/components/ui/dropdown-menu` is
`DropdownMenu`, `@/lib/browser-storage` is `BrowserStorage`, `../theme.ts` is `Theme`. Member access
carries the prefix even when that reads redundantly: `Button.Button`, `Input.Input`, `App.App`. The
prefix is the point — it says where a name came from without a jump to the import block, and it is
what keeps a module free to add exports without colliding with its consumers' locals.

The rule has a consequence worth stating outright: **do not `export default`.** A default import
cannot be namespace-qualified, so a default export puts the module permanently outside the
convention. `apps/frontend/src/App.tsx` is exported by name for exactly this reason. The one
standing exception is a tstyche template (`test/**/*.tst.ts`), which tstyche reads from the default
export — a tool contract, like case 3 below.

Unqualified is correct in four cases, and only these:

1. **Test DSL** — `@effect/vitest` (`describe`/`it`/`expect`), `@effect/vitest/utils`
   (`strictEqual`), `@testing-library/react` (`render`/`fireEvent`/`waitFor`/`within`), and
   `vitest/config` (`defineConfig`/`mergeConfig`). These read as syntax at a call site that is
   nothing but call sites; a prefix on every assertion line buys nothing.
2. **`effect/Function`** — `pipe`, `identity`, `flow`, `dual`, `constVoid`. Same reasoning.
3. **Third-party modules that only offer a default export** — `@tailwindcss/vite`,
   `@vitejs/plugin-react`. A namespace object is not callable, so this is a language limit rather
   than a preference. It does not license a _new_ default export in this repo; see above.
4. **Bare side-effect imports** — `import "@/index.css"`.

A namespace whose members are all used in type position needs `import type * as Name` —
`typescript/consistent-type-imports` is an error and does not care that the import is a namespace.
`ModeToggle.tsx` is the frontend's live example.

`vite.config.ts`, `vitest.config.ts`, `vitest.shared.ts` and `vitest.setup.ts` are covered entirely
by cases 1 and 3, so they need nothing.

**`apps/frontend/src/components/ui/**` is exempt.** Those files are vendored shadcn output that the
CLI overwrites on every `add`/`update` — `.oxlintrc.json` already carves them out under a
`// Managed by shadcn` override for the same reason. Leave their internals in upstream form;
everything importing _from_ them still does so qualified.

`tsconfig.base.json`'s `namespaceImportPackages` steers the language service's auto-imports toward
this form. It matches package names only, so the `@/*` alias and relative specifiers are on you.

## Effect code

The four Effect units (`domain`, `db`, `supabase`, `server`) share these, and a new module that breaks one reads
as the odd one out:

- **No mutation.** No `let`, no `for`, no `.push`, no `.forEach`. Build with `pipe` and `effect/Array`; a batch of
  effects is `Effect.forEach`, not a loop. Where a module's name collides with a JavaScript built-in, the module takes
  the plain name and the built-in is written `globalThis.X` — `import * as Array from "effect/Array"` alongside
  `globalThis.Array<T>`.
- **`Effect.fn("<Service>.<method>")` over a returned `Effect.gen`.** `Effect.gen` is fine inside a service's `make`
  or a group's builder; a method may not _return_ a bare `Effect.gen`. `Effect.fn` wraps it and names the span in the
  same stroke; a method built as a pipeline ends with `Effect.withSpan("<Service>.<method>")`.
- **Errors are values.** `Schema.TaggedError` for every failure; no `throw`, no `try`/`catch`. A promise boundary is
  `Effect.tryPromise` with a `catch` that maps to a tagged error. A method's error channel is written out in full and
  never widened to `unknown`.
- **Model in `Schema`.** Sum types are `Schema.Union` of tagged members or `Data.TaggedEnum` — never a `kind` field
  beside correlated optionals, never a boolean standing in for a variant, never a hand-written `_tag`. If a docstring
  asserts an invariant, the type enforces it.
- **Lift nullish.** `Option.fromNullishOr` and match, including at driver and SDK boundaries. Comparing to `null` or
  `undefined` is the habit this displaces.
- **Layers read config; they are not functions of it.** Every layer looks its values up through the ambient
  `ConfigProvider`. No `Config.withDefault`: the launcher names every value, and a missing one stops the process.
- **Identifiers are fully qualified**: `"@replaceme/<pkg>/<Module>"` on every `Schema.Class`, `TaggedError` and
  `Context.Service`, with a folder carried (`"@replaceme/domain/TopLevel/Api"`). Renaming the scope renames the prefix
  and nothing else.
- **Every `@since` reads `0.0.0`**, uniformly, because nothing is published and the tag has no referent yet. A full
  JSDoc block on every public export, with `@since` and `@category`.
- **A docblock states what is true of this file now and cites no other file.** Invariants and non-obvious constraints
  only: no changelogs, no arguments with a prior version, no cross-file citations, no unverified `TODO`. Load-bearing
  words are set in CAPS (`REQUEST-scoped`, `ON PURPOSE`) to mark the sentence a reader must not skim past.

## Tests

Every unit merges `vitest.shared.ts`, so these hold everywhere:

- **`sequence.concurrent` is on**, so tests within a file run at the same time.
- **`globals` is not set**, so libraries that rely on implicit global hooks do not get them —
  `@testing-library/react` never registers its automatic `afterEach(cleanup)`, for one.
- Collection is `test/**/*.test.ts` per unit. `exclude` **replaces** Vitest's default list rather
  than extending it, which is why `**/node_modules/**` and `**/dist/**` are restated there.
- `vitest.setup.ts` runs for every project and calls `addEqualityTesters()`.
- Tests import `describe`/`it` from `@effect/vitest`, not from `vitest`. Assertion helpers come from
  `@effect/vitest/utils` (`strictEqual`, `deepStrictEqual`, `assertSome`, ...). Swap a layer where the instinct is
  to mock; assert a failure through `Effect.flip`.
- `test/**/*.tst.ts` are tstyche type tests, run by `pnpm test:types` and invisible to vitest. `pnpm test:types` is
  part of the gate beside `check`, `lint` and `test`.

`tsconfig.tests.json` globs `packages/*/test/**/*.ts` and `apps/*/test/**/*.ts`. Its `paths` block
resolves every workspace package regardless of declared dependencies — deliberately, as the escape
hatch for `internal/*` and cyclic test dependencies. The cost is that `pnpm check` will not catch a
test importing a package its unit does not depend on. Vitest will.

## Adding a package

1. Copy `packages/lib` to `packages/<name>` and rename it in `package.json` and `<name>.nix`.
2. Add `{ "path": "packages/<name>" }` to `tsconfig.packages.json`.
3. Add `./packages/<name>/<name>.nix` to `imports` in `flake.nix`.
4. If it has tests importing other workspace packages, add its `paths` entries to
   `tsconfig.tests.json`.

That is the whole checklist — `pnpm-workspace.yaml` and `vitest.config.ts` glob `packages/*`
already.

`packages/lib` is the copy source for a new package: one module, one test, and the unit `.nix` in its
canonical shape. A unit with `workspace:` dependencies also lists each one in its `.nix` (see below)
and declares the matching `references` in its `tsconfig.json`.

The placeholder tokens a fork renames are exactly four; README.md carries the recipe.

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
`ERR_MODULE_NOT_FOUND`. Bundle the app, or rewrite the manifests on the way out. `apps/server` does
the former for its Worker entry point: `esbuild` is a devDependency of that unit (through the root
`catalog:`, pinned to the esbuild Vite already resolves) rather than a dev-shell tool, because it is
a build input of one unit and not something a human runs.

## Nix builds

Each unit's `<name>.nix` declares its own dependency closure twice: `pnpmWorkspaces` (which
workspace projects to fetch) and `extraSrcs` (which files to expose). `buildPnpmPackage` narrows
`pnpm-workspace.yaml` to just those projects before fetching, so a unit's fixed-output hash depends
only on its own closure rather than the whole repo's.

`extraSrcs` lists files explicitly rather than passing a bare directory: a bare directory sweeps
`node_modules/` and a stale `dist/` into the sandbox, which would silently satisfy `tsc -b`
incrementality. A unit with `workspace:` dependencies lists each dependency's package name in
`pnpmWorkspaces` and its `package.json`, `tsconfig.json` and `src` in `extraSrcs`, because `tsc -b`
follows the unit's `references` and builds them first; `packages/supabase/supabase.nix` is the
one-dependency example and `apps/server/server.nix` the three-dependency one.

`buildPnpmPackage` exposes `passthru.nodejs`, the Node the unit was built against, so anything that
runs a unit's output (the server's NixOS module) takes `package.nodejs` rather than naming a second
Node attribute.

A unit may compose another unit's OUTPUT in Nix without depending on it in pnpm:
`packages.server-worker` in `apps/server/server.nix` is a `runCommand` over `packages.server` and
`packages.frontend`. That keeps the frontend a bundler leaf while giving the deploy one directory
to upload. `checks` includes every package, composed ones too.

**Changing dependencies changes the hash.** Set `hash = pkgs.lib.fakeHash;`, run the build, and
paste the reported hash back in. A stale hash surfaces as `ERR_PNPM_NO_OFFLINE_TARBALL` from inside
the build; `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` instead means `pnpm-lock.yaml` is out of sync with
`pnpm-workspace.yaml`'s catalogs and needs a plain `pnpm install` first.

Working directory inside the derivation mirrors the repo root, so a package at `packages/lib`
builds into `./packages/lib/dist`.

`prepare` runs `effect-tsgo patch`, which patches the TypeScript binary so the Effect
language-service plugin contributes diagnostics. Nix builds install with `--ignore-scripts`, so
`prepare` never runs there and `nix build` type-checks with unpatched `typescript`. `pnpm check`
locally is therefore slightly stricter than the sandbox. Add
`preBuild = "pnpm exec effect-tsgo patch";` to a unit's `.nix` if you want parity — the patch is
purely local file manipulation and is sandbox-safe.

## Setup wizard as a readiness probe

Two wizards share one contract: `Setup.command` (macOS, double-clickable from Finder) and
`Setup.cmd` + `Setup.ps1` (Windows 11, double-clickable from Explorer; the `.cmd` is only the
launcher for the `.ps1`). Both are the human's guided first-time setup (README.md links them),
and both are the same file again as an agent readiness probe: with stdin redirected, every
mutation defaults to skip — toolchain build, dependency install, health check, Nix settings
write, the Claude-app walkthrough, the GitHub access chain (history init, remote wiring,
sign-in), and on Windows also the WSL/Ubuntu/Nix installs and the copy of the project into the
distro — so nothing is mutated and the output reports which stages are already satisfied,
ending with a "still to do by hand" list of runnable commands.

The skip-and-report list is the non-interactive contract only. Run interactively, `Setup.ps1`
stops loudly at the first stage that fails (exit 1) — every stage depends on its predecessors,
so continuing would only cascade one failure into many. The one exception is the health check,
whose remedy is the Claude app that a later stage installs. `Setup.command` still records and
continues; port the fail-fast behavior if that ever grates.

Probe invocations:

- macOS: `bash Setup.command </dev/null`
- Windows, from cmd/PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File Setup.ps1 < NUL`
- From an agent inside the WSL distro (the normal case on Windows — interop):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w ./Setup.ps1)" </dev/null`

The PowerShell probe adds the Windows-only facts (WSL enabled, Ubuntu provisioned, Claude app
installed); distro-only state can equally be probed directly with bash (`test -e .devshell/bin`
and friends). `bash Setup.command </dev/null` run inside WSL exits 0 at its macOS gate —
expected, not an error. On Windows the wizard lives in and copies the project to the distro's
own filesystem (`~/<folder>`); the unzipped folder on the Windows drive is only the launcher,
and `/mnt/c` is never the working copy.

The stages that prompt interactively (installing Nix, WSL, Ubuntu, account sign-ins) are
privileged or account-bound: they belong to the human, who runs the wizard themselves — tell
them to when a stage they need is unsatisfied.

## Agent configuration

The dev shell's `shellHook` exports `CLAUDE_CONFIG_DIR="$PWD/.claude"` when entered from the
repo root, so Claude Code started from a `nix develop` or `direnv` shell keeps its config and
session state inside the repo. Desktop and IDE clients ignore this and use `~/.claude`, so
`./.claude` is only the live config directory for terminal sessions.

There is no custom sandbox wrapper. Claude Code's own sandbox — configured in
`.claude/settings.json`, see the next section — is the only one, which is why that file is
tracked.

Because `./.claude` can be `CLAUDE_CONFIG_DIR`, it mixes tracked project config with runtime
state. `.gitignore` ignores `.claude/*` and re-includes only `settings.json`, `launch.json`,
`hooks/`, `commands/`, `agents/`, `skills/` and `output-styles/`, so credentials and session
history stay out of git while a clone still gets the workflow boundary. Add a re-include when you
add a new config directory there.

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

The toolchain also bundles `bash`, coreutils, findutils, GNU `grep` and GNU `sed`, and the hook
scripts prepend `.devshell/bin` to their PATH when the out-link exists. Building it once therefore
also pins the tools hooks run with in GUI-launched clients, whose PATH is otherwise the host's
(Apple bash 3.2, BSD userland) — the scripts stay compatible with both, and `bin/test-hooks.sh`
exercises the guards in each mode.

<!-- BEGIN openspec-boundary -->

## Workflow: OpenSpec is the source of truth

OpenSpec owns the idea-to-code chain in this project. Every planning artifact lives in
`openspec/changes/<change-name>/` — those are the only planning documents that get synced into
living specs and archived. Open an OpenSpec change only when asked to.

- design → `openspec/changes/<change-name>/design.md`
- plan → `openspec/changes/<change-name>/tasks.md`

Artifacts describe the work, not who runs it — never embed an executor directive in one.
`/opsx:apply` is the only executor.

A PreToolUse hook at `.claude/hooks/boundary-guard.sh` enforces the artifact boundary: writing a
plan or design document elsewhere (`docs/plans/`, `docs/specs/`), by file tool or shell
redirection, is denied. The denial message names the correct location; follow it rather than
looking for a way around.

One operational note: `/apply` must run in a fresh chat. When a proposal is complete, tell the
user to begin a new chat and use `/apply` there — everything needed is on disk, and a large
planning transcript is the main cause of slow apply runs. This is enforced, not advisory: a hook
at `.claude/hooks/fresh-session-guard.sh` blocks `/apply` in any chat where a proposal ran.

The `.claude/commands/opsx/*.md` commands and `.claude/skills/openspec-*` skills are vendored —
`openspec update` regenerates them, so never edit them. Local behavior (the lay-facing phase
endings, the fresh-chat rule) layers on top instead, in the `/propose`, `/apply` and `/archive`
alias commands, the hooks, and the Guided output style.
<!-- END openspec-boundary -->
