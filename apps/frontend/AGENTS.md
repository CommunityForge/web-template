# apps/frontend

**Framework:** Vite + React 19 + Tailwind 4 SPA.

## It is a leaf, not a project reference

`tsconfig.app.json` and `tsconfig.node.json` extend `../../tsconfig.base.json` and switch off its
emit options (`composite`, `declaration`, `declarationMap`, `sourceMap`): Vite resolves and emits,
`tsc -b` only type-checks. This app is deliberately absent from `tsconfig.apps.json`'s `references`.

- `strict` and `exactOptionalPropertyTypes` come from the base. Fix the source, don't weaken them.
- `@effect/language-service` is inherited. Setting `compilerOptions.plugins` here **replaces** it
  rather than merging — restate it if you ever do.
- `@/*` → `src/*` is declared in **three** live places: `tsconfig.app.json` `paths`,
  `vite.config.ts` `resolve.alias`, `vitest.config.ts` `resolve.alias`. tsc, bundler and test runner
  resolve independently; change all three. A fourth, inert copy sits in `tsconfig.json` — see shadcn.
- Aliased imports take **no extension** (`@/components/ui/button`); relative ones do
  (`./features/counter/index.ts`). `allowImportingTsExtensions` only rewrites relative specifiers, so
  a `.tsx` on a path-mapped import is `TS2877`.

## Routing

React Router in **declarative mode** — `<BrowserRouter>` + `<Routes>`/`<Route>`. No loaders, no
actions, no `RouterProvider`, no SSR. `<BrowserRouter>` mounts in `main.tsx`; `App.tsx` holds only
the `<Routes>` tree, which keeps `App` renderable under `<MemoryRouter>` in tests. There is no
`routes.tsx` — in declarative mode `App` _is_ the route table.

- **Adding a route**: component in `src/routes/`, a module-scope `const` for its element, one
  `<Route>` line in `App.tsx` above the `path="*"` catch-all, which must stay last.
- **Route elements are hoisted** (`const HOME = <Home />`). `react-perf/jsx-no-jsx-as-prop` is an
  error repo-wide; hoisting is the fix that rule wants, not a workaround.
- **`RegistryProvider` sits outside `BrowserRouter`.** The Atom registry is app-scope
  infrastructure; nesting it inside the router ties atom lifetimes to navigation, and atoms are
  reference-counted (below).
- **Not available in declarative mode**: `ScrollRestoration`, `createRoutesStub`. Check any other API
  against the availability table in `node_modules/react-router/docs/start/modes.md`.
- **Deep links need a host rewrite.** `vite dev`/`preview` fall back to `index.html`;
  `nix build .#frontend` only emits `dist/`, so whatever serves it must rewrite unknown paths.
  `HashRouter` would remove the requirement at the cost of `#` URLs.

If you need to learn more about particular React Router apis and concepts that the
above doesn't cover, search through the source code in `node_modules/react-router/docs`.

## Effect and Atom

State lives in `Atom`s, not React. `useState` remains correct for ephemeral, view-local,
consequence-free state (dialog flags, focus bookkeeping, DOM measurement); anything crossing a
component boundary, async, effectful, owning a resource, or surviving unmount must be an `Atom`.

- **Query-string state belongs to Atom, not the router.** Use `Atom.searchParam(name, { schema })`;
  never `useSearchParams`. The router owns path matching; `?param=` is application state.
  `Atom.searchParam` writes `window.history` directly, which declarative-mode React Router does not
  observe — safe, since only the query string changes and the matched route is stable, but it means
  reading the query through `useLocation`/`useSearchParams` returns stale values. One owner: if any
  code reads a param through the router, that param's writes must go through the router too — so
  they don't.

Conventions must follow from the `effect-atom-react` skill.

## shadcn, UI & styling

Use the `shadcn` skill where appropriate to understand particulars about component usage. Shadcn
components are preferred over custom components wherever possible.

## Linting and tests

Tests are `test/*.test.tsx` under happy-dom. `vitest.config.ts` restates the React plugin because it
replaces `vite.config.ts` rather than merging. The repo-wide rules in the root `AGENTS.md` apply;
these are their React and Atom consequences:

- **Scope queries with `within(container)`.** Tests in a file run concurrently and
  `@testing-library/react` never registers its automatic `afterEach(cleanup)`, so renders coexist in
  `document.body` and a bare `screen.getByRole` matches across all of them — surfacing as "found
  multiple elements", not a clean failure.
- **Mount a `RegistryProvider`** in any test asserting an absolute value, or atoms resolve against
  `@effect/atom-react`'s module-scope fallback registry, shared and mutated by every concurrent test
  in the file.
- **Assert atom updates inside `waitFor`.** The registry batches notifications through React's
  scheduler at low priority, so re-renders land after `fireEvent` returns.
- **Wrap anything using a router hook in `<MemoryRouter>`**, or `useRoutes()` throws. Its default
  `initialEntries` is `["/"]`; hoist any override to module scope, per `jsx-no-new-array-as-prop`.
- **Use `.tsx` for tests.** Root `tsconfig.tests.json` globs `apps/*/test/**/*.ts` only, so a `.tsx`
  test is owned solely by this unit's `tsconfig.app.json` and cannot end up in two projects.
- **`localStorage` works only because of `execArgv`.** Node >= 25 ships a `globalThis.localStorage`
  that shadows happy-dom's, and Vitest 4 drops any window key already present on the global, so
  `vitest.config.ts` passes `--no-experimental-webstorage`. Remove it and every storage-backed atom
  silently reads `undefined`. happy-dom's `Storage` is per-`Window`, hence fresh per test file --
  do not assume that if the flag is ever swapped for `--localstorage-file`, which is process-wide.

## Dependencies and Nix

Catalogs gate the Effect line, `typescript`, `vitest`, `@types/node`. React, Vite and Tailwind are
pinned with ordinary ranges here — intentional.

`nix build .#frontend` emits the static bundle to `$out`; its `checkPhase` runs `check`,
`test --run` and `oxlint --type-aware`.
