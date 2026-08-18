---
name: effect-atom-react
description: Architecture and reactivity patterns for building React (or Astro-island) frontends on Effect v4 with Atom (`effect/unstable/reactivity/Atom`) and `@effect/atom-react`. Use this skill whenever the task involves React components in an Effect codebase, Atom/AtomRegistry/AsyncResult, `useAtomValue`/`useAtomSet`/`useAtomSuspense`, deciding where state should live (hook vs. atom), wiring services or layers to UI, managing resources like editors/terminals/websockets from React, data fetching or mutations in an Effect frontend, or structuring feature folders in a React+Effect app — even if the user never says the word "atom". Also use it when reviewing or refactoring React code in an Effect project for anti-patterns (fetch-in-useEffect, dependency arrays, state duplication). For core Effect questions unrelated to UI (schemas, error handling, testing, server-only layers), defer to the effect-ts skill; use both together when a task spans UI and core.
---

# Effect + Atom React Architecture

Patterns for building React frontends where Effect is the application framework and React is only the render layer. Distilled from the Effect-TS `website` repository (the reference implementation maintained by the Effect team) and verified against the Effect v4 sources.

The one-sentence philosophy: **all application semantics — state, async, resources, orchestration, persistence — live in Effect land (services, layers, fibers, scopes) and in the Atom reactive graph; React components are thin subscribers.** When this holds, entire classes of React bugs (stale closures, dependency arrays, fetch races, effect-cleanup leaks, state synchronization) become unexpressible rather than merely avoided.

## Prerequisite

This skill assumes Effect v4 (`effect@beta`; every API claim here was verified against `4.0.0-beta.107` sources) where Atom lives in core at `effect/unstable/reactivity/Atom`, with React bindings from `@effect/atom-react` at the **same aligned version**. If the project uses the older standalone `@effect-atom/atom` packages, the concepts transfer but names differ (`Rx` → `Atom`, `Result` → `AsyncResult`). If the `effect-ts` skill is available, follow its setup and core-Effect conventions; this skill only adds the UI layer. When a signature matters, confirm it against `node_modules/effect/src/unstable/reactivity/*.ts` — the sources in the repo outrank this document.

## The two facts that make everything work

1. **Reading is subscribing.** Inside an atom's read function, `get(otherAtom)` both returns the value and registers a dependency. There are no dependency arrays because the act of reading *is* the declaration — you cannot forget a dep. Intentional non-reactivity is a distinct, greppable call: `get.once(atom)`. Prefer this over hooks precisely because it removes the exhaustive-deps bug class instead of linting it.

2. **Lifetime is reference-counted and scoped.** Atoms are lazy: built on first subscription, disposed shortly after the last subscriber leaves (the default React registry uses a 400 ms idle TTL; a `RegistryProvider` you mount yourself disposes immediately unless you pass `defaultIdleTTL`). Effectful atoms run inside a `Scope`, so disposal is real resource cleanup — `Effect.forkScoped` fibers are interrupted, `Effect.acquireRelease` finalizers run, `get.addFinalizer` callbacks fire. Opting out is explicit and rare: `Atom.keepAlive` to pin, `Atom.setIdleTTL("10 seconds")` to keep expensive resources (an editor, a connection) alive across brief unmounts.

## The architecture law

Organize by vertical feature slice, with strict one-way layering inside each slice:

```
features/<feature>/
  domain/       Pure model: Schema classes, branded types, tagged errors.
                No React, no services, no atoms.
  services/     Context.Service classes + layers. No React. May touch atoms
                only via the AtomRegistry service.
  atoms/        The reactive wiring: runtimes, families, fn atoms.
                Imports domain + services. Still no React.
  components/   React. Consumes atoms via hooks. Never imports a service.
  index.tsx     Public entry point (the island/root component).
```

**React never imports a service.** If a component needs a capability, expose it as an atom (usually an `Atom.fn` command) or as a method on a handle produced by an atom. This single rule keeps components testable, keeps effects cancellable, and prevents the "async handler soup" that grows in conventional React apps. When you find a component reaching for a service or doing its own `fetch`, that is the signal to add an atom, not an exception to make.

Cross-cutting client/server features (search, RPC endpoints) live in `src/services/<name>/` with a shared-contract split: `domain.ts` (shared Schema types/errors), `rpc.ts` or an HttpApi definition (the contract), `service.ts` + `rpc-server.ts` (server), `client.ts` (browser service). Client and server share *only* the schema contract. Read `references/architecture.md` before laying out a new feature or a client/server service — it has the full anatomy, the Astro/island integration notes, and the API-route adapter pattern.

## Where state lives: the decision procedure

Hoist state into an **atom** if any of these hold: it crosses a component boundary; it is asynchronous or effectful; it owns or touches a resource; it must survive unmount; it must persist (localStorage/URL); it is derived from other reactive state; it is written by a service or background process. When in doubt, choose the atom — nothing important should ever be trapped in a hook where unmount destroys it.

Keep state in **React hooks** only when it is ephemeral, view-local, synchronous, and consequence-free: dialog/popover open flags, an accordion's expanded boolean, focus and scroll bookkeeping, DOM measurement, animation presentation values. `useEffect` is legitimate only as boundary glue: wiring `window`/custom events from a non-React shell into an island, mirroring local state into DOM attributes, focus management. If a `useEffect` fetches data, subscribes to application state, synchronizes two pieces of state, or constructs a resource — move that logic into an atom.

## The essential idioms (recognize and reach for these)

Read `references/atom-api.md` for full signatures and worked examples of each; the list below is for recognition.

- **Plain and derived state**: `Atom.make(value)`; `Atom.make((get) => ...)` for computed values; `Atom.map` for single-input derivation; `Atom.writable(read, write)` for lens-like derived writables; `Atom.debounce` as a graph combinator (never `setTimeout` in a component).
- **External event sources as self-cleaning atoms**: wrap MutationObserver/matchMedia/hashchange/ResizeObserver in `Atom.make((get) => { ...; get.addFinalizer(...); return initial })` with `get.setSelf` on events. One subscription per registry, not per component.
- **Async as data**: an atom whose read returns an `Effect` or `Stream` has value `AsyncResult<A, E>` — three states (`Initial`/`Success`/`Failure`), each carrying a `waiting` flag, so "refreshing" is Success-with-waiting rather than a fourth state. Derive spinners and error UI from it; never hand-manage `isLoading`/`error` state. Query pipelines are atom chains (`query → debounce → effect`), and the registry interrupts stale effects automatically. When you want query-library cache semantics (stale time, refetch on focus), that is `Atom.swr` — not a second library.
- **Runtimes**: `Atom.runtime(Layer.mergeAll(...))` per feature-boundary layer set; `runtime.atom(effect)` for scoped effectful values; `runtime.fn<Args>()(...)` for commands. Runtimes from the default factory share a per-registry Layer MemoMap, so within a registry a layer defined once and imported everywhere is **built once** across runtimes — define each layer exactly once as a `static readonly layer` on its service class.
- **Commands are `Atom.fn`**: typed input, typed errors, invoked via `useAtomSet`, status as `AsyncResult`. Put post-mutation bookkeeping (selection changes, cache updates) *inside* the command with `get.set`, next to the mutation.
- **Per-entity state**: `Atom.family((arg) => ...)` — memoized by structural equality, WeakRef-GC'd, referentially stable, therefore safe to call during render.
- **Bridging the DOM**: an `Atom.make(Option.none<HTMLElement>())` element atom, a callback ref calling `useAtomSet`, and `yield* get.some(element)` in the effect atom to suspend until the element exists. This is how imperative libraries (Monaco, xterm, maps, charts) mount — never a ref + `useEffect` dance.
- **Persistence**: `Atom.kvs({ runtime, key, schema, defaultValue })` for schema-validated localStorage; `Atom.searchParam(name, { schema })` for URL params. Persistence is declarative and validated at the boundary.
- **The handle pattern**: for a subsystem (a workspace, a session, a document), one family atom whose success value is a bundle of capabilities — inner atoms, `Atom.fn` commands, plain effect methods — all scoped to the parent atom's lifetime. React receives the handle once via `useAtomSuspense` and passes it through context.

## React consumption rules

Use `useAtomValue(atom)` to read (and its selector overload `useAtomValue(atom, (a) => a.slice)` to narrow re-renders — **the selector must be a stable, module-level function**: the hook memoizes `Atom.map(atom, f)` on the function's identity, so an inline arrow re-subscribes on every render); `useAtom` for value+setter; `useAtomSet` for setters and command invocation (it also mounts the atom, and in the default mode the setter accepts an updater function); `useAtomMount(atom)` to keep a background atom (an editor, a sync loop, an autosave) alive for a component's lifetime without reading it; `useAtomSuspense` for Suspense-integrated loading of `AsyncResult` atoms — it returns the `Success` object (read `.value`) and **throws failures**, so pair it with an error boundary; `AsyncResult.builder(result).onSuccess(...).onFailure(...).render()` for explicit top-level branching (`.exhaustive()` type-errors until every possible case is handled).

**Context carries stable handles; atoms carry change.** A React context should hold an immutable definition or a capability bundle created once — never values that change over time. Changing data flows through atoms read with selectors, so re-renders are per-subscription rather than per-subtree. This is why the pattern doesn't suffer the context-as-store re-render storm. `@effect/atom-react` packages this as `ScopedAtom`: its top-level `make(factory)` export (note: *not* `Atom.make`) returns a `{ Provider, Context, use }` trio whose atom is created once per provider subtree.

## Services and layers (UI-relevant specifics)

Follow the effect-ts skill for core conventions (Context.Service class syntax, namespaced ids, tagged errors). The UI-specific additions:

- Every exported layer pre-provides its own dependencies (`Layer.effect(this, this.make).pipe(Layer.provide(Dep.layer))`) so runtime boundaries compose flat `Layer.mergeAll` lists.
- Services participate in reactivity by requiring the `AtomRegistry.AtomRegistry` service (available automatically inside `Atom.runtime` layers) and calling `registry.get/set/update` — or the Effect-returning `Atom.get/set/update` module functions — on module-level atoms. This is the sanctioned channel for background processes (stream consumers, tracers, watchers) to drive UI.
- Scope tiers to keep straight: the runtime-atom scope (layer builds/teardowns with subscription), per-handle scopes (subsystem resources die with their handle atom), and caller-decided scopes (methods returning `Effect<A, E, Scope.Scope>` let the calling atom own the resource). Escapes (`Effect.forkDetach`, `Effect.uninterruptible`) are deliberate and commented.
- Tracing in atom read functions is a project convention, not a law: the Effect team's site uses `Effect.fnUntraced` there (hot paths where a span adds noise), while other projects — including this monorepo, per `apps/frontend/AGENTS.md` — prefer named `Effect.fn("Namespace.method")` spans everywhere. Check the project's AGENTS.md and follow it; either way, keep named spans on server/business logic. Append `Effect.tapCause(Effect.logError)` to effectful atoms so failures are never silent.

## Anti-patterns to refuse or refactor

When writing new code, do not produce these; when reviewing, flag them with the atom-based replacement: fetch-in-`useEffect` (→ effect atom with abort via the registry); `isLoading`/`error`/`data` state triples (→ `AsyncResult`); `useEffect` that synchronizes one state into another (→ derived atom); event listeners per component instance (→ external-source atom); resource construction in effects with manual cleanup (→ `acquireRelease` in a scoped atom); per-entity state in lifted Maps or keyed remounts (→ `Atom.family`); changing values in React context (→ stable handle + atoms); a second state library alongside Atom (→ one store; Atom covers state, queries, mutations, persistence, URL). `references/patterns.md` has the full pattern↔anti-pattern catalog with code for both sides — read it when reviewing existing React code or when justifying a refactor to a team.

## References

- `references/atom-api.md` — the Atom constructor/context vocabulary with worked examples (runtimes, families, fn atoms, element atoms, kvs/searchParam, AsyncResult, the `get` context, lifecycle modifiers). Read before writing any non-trivial atom.
- `references/architecture.md` — feature-slice anatomy, client/server service split with RPC/HttpApi, Astro island integration, layer scoping and MemoMap reuse, tooling posture. Read before structuring a feature or wiring client to server.
- `references/patterns.md` — the pattern↔anti-pattern catalog plus advanced material (the handle pattern in full, tracing-as-UI, progressive-loading choreography, persistence chains). Read when reviewing code, refactoring, or looking for a known solution to a stubborn UI problem.
