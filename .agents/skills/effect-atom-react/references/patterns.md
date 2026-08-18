# Pattern ↔ Anti-Pattern Catalog, plus Advanced Patterns

Use this file when reviewing React code in an Effect project, when refactoring, or when a UI problem feels stubborn — it may have a known shape. Each entry names the pattern, the conventional-React anti-pattern it replaces, and why the replacement is structural rather than stylistic.

## Contents

1. The catalog (quick table + details)
2. The handle pattern in full
3. Tracing as a UI mechanism
4. Progressive-loading choreography
5. Persistence and import chains
6. Known warts and honest caveats

## 1. The catalog

| Do this | Instead of | Bug class eliminated |
| --- | --- | --- |
| `get(atom)` dependency tracking; `get.once` for intentional snapshots | `useEffect`/`useMemo`/`useCallback` dep arrays | Non-exhaustive deps, stale closures |
| `AsyncResult` atom values | `isLoading`/`error`/`data` useState triples | Impossible states, race bookkeeping |
| Query pipelines as atom chains (query → debounce → effect with abort signal) | fetch-in-`useEffect` | Races, StrictMode double-fires, no cancellation, setState-after-unmount |
| `acquireRelease` + `forkScoped` in scoped atoms; `setIdleTTL` cache policy | effect-cleanup closures per component; hoisted singletons | Leaked observers, disposal-order bugs, re-init churn |
| Element-Option atoms + `get.some` | `useRef` + `useEffect` mounting choreography | Ref-ordering puzzles, `if (!ref.current)` guards |
| `Atom.family` per-entity state | lifted `Map<id, State>`, keyed remounts, state lost on unmount | Identity and lifetime bugs |
| Stable handles in context, atoms for change, selectors to narrow reads | context-as-store | Whole-subtree re-render storms |
| Commands as `Atom.fn` with typed inputs/errors and in-command bookkeeping | `async onClick` + try/catch + scattered post-mutation logic | Floating promises, swallowed errors, duplicated bookkeeping |
| External sources as self-finalizing atoms | per-instance `addEventListener` effects | N subscriptions, missed cleanups |
| `Data.taggedEnum` UI modes; branded/Schema domain types | boolean-flag combinations; unvalidated `JSON.parse` | Impossible states; corrupt persisted data |
| Tagged errors + `catchTag` + `tapCause(logError)` at atom boundaries | `catch (e) { console.error(e) }` | Silent failures, untyped recovery |
| One store (Atom) | Atom + Redux/Query/Zustand side by side | Multi-store synchronization |

### Details worth internalizing

**Dependency tracking.** The reason this is structural: in a hook, the dependency list is a *separate artifact* you must keep in sync with the closure; in an atom, reading and depending are the same operation, so there is nothing to desynchronize. And where a hook developer silences the lint rule, an atom developer writes `get.once` — a positive, searchable statement of "I want the current value, not a subscription." When porting a `useEffect`, every value it closes over becomes either a `get(...)` (reactive) or a `get.once(...)` (snapshot); making that choice explicitly usually reveals the bug the effect had.

**Async as data.** A refreshing `AsyncResult` stays `Success` with `waiting: true` and keeps its previous value, so "show stale data while refreshing" is free (`result.waiting && <Spinner/>` over the old list) — a feature that takes a query library or careful ref juggling to replicate in hook land. When you need actual query-cache policy (stale time, refetch on window focus), `Atom.swr` adds it to any async atom.

**Commands own their consequences.** After a `createFile` mutation, selecting the new file; after `removeFile`, repairing a dangling selection — these live *inside* the fn atom with `get.set`, adjacent to the mutation. In conventional React this logic scatters across the components that happen to call the mutation, and drifts. The self-resetting button (fork a sleep, `get.setSelf(AsyncResult.initial())`) is the same principle applied to UI feedback — and when the *caller* should decide, writing the `Atom.Reset` symbol to the fn atom resets it from outside.

**Honest local state.** The discipline is not "never useState." Dialog open flags, an accordion's expanded boolean, focus bookkeeping, DOM measurement, animation presentation values — these are ephemeral, view-local, synchronous, and consequence-free, and plain hooks are the *right* tool. The test: would losing this state on unmount lose user data or interrupt an operation? If yes, it belongs in an atom.

## 2. The handle pattern in full

For a subsystem with identity and lifetime (a workspace, a session, a document, a connection): one `Atom.family` keyed by the subsystem's definition, whose runtime atom yields a **handle** — a bundle of capabilities scoped to that atom's life.

```ts
export interface WorkspaceHandle extends Atom.Success<ReturnType<typeof workspaceHandleAtom>> {}

export const workspaceHandleAtom = Atom.family((workspace: Workspace) =>
  runtime.atom(
    Effect.fnUntraced(function* (get) {
      const container = yield* WebContainer
      const handle = yield* container.createWorkspaceHandle(workspace)   // handle-scope resources

      const selectedFile = Atom.make(workspace.initialFile)              // atoms created in-scope

      // Reactive invariant maintenance: keep selection valid as files change
      get.subscribe(handle.workspace, (next) => {
        if (Option.isNone(next.pathTo(get.once(selectedFile)))) {
          get.set(selectedFile, firstFileOf(next))
        }
      })

      return {
        selectedFile,
        workspace: handle.workspace,
        createFile: Atom.fn<CreateArgs>()(Effect.fnUntraced(function* (args, get) {
          const node = yield* handle.createFile(...args)
          if (node._tag === "File") get.set(selectedFile, node)          // consequence lives here
        })),
        removeFile: Atom.fn<File | Directory>()(...),
        readFile: handle.readFile,
      } as const
    }),
  ),
)
```

React side — the entire bridge is a few lines:

```tsx
export function WorkspaceProvider({ workspace, children }) {
  const handle = useAtomSuspense(workspaceHandleAtom(workspace)).value
  useAtomMount(autoSaveAtom(handle))          // keep background loops alive while mounted
  return <WorkspaceContext.Provider value={handle}>{children}</WorkspaceContext.Provider>
}
// Consumers: const { selectedFile } = useContext(WorkspaceContext); useAtomValue(selectedFile)
// Narrow reads with selectors: useAtomValue(handle.workspace, (ws) => ws.tree)
```

Why it works: the context value is created once (stable — no re-render storms); every changing value flows through an inner atom; every resource, fiber, and invariant-maintenance subscription dies with the handle atom's scope when the last consumer unmounts. Families of handles compose — a handle can itself contain an inner `Atom.family` (e.g., `createTerminal(shell)` returning element+terminal atom pairs per shell).

Export the handle's type via `Atom.Success<ReturnType<typeof theAtom>>` so downstream atoms (in other files) can accept it without circular imports.

When the handle is a plain atom (no `Atom.family` keying, no suspense on an async result), `@effect/atom-react`'s `ScopedAtom` (`make(factory)`) packages the Provider/Context/use wiring for you — the provider creates the atom once for its subtree and `use()` retrieves it. Reach for the hand-rolled version above when the handle comes from a family or needs `useAtomSuspense`.

## 3. Tracing as a UI mechanism

Two transferable ideas:

- **Spans as UI events.** Install a custom `Tracer` in a layer; when a span carries a known annotation (`Context.getOrUndefined(span.annotations, MyStepKey)`), write to state atoms on span start/end/event. The same instrumentation then drives both telemetry and UI (animations, progress, waterfalls). Business code stays clean — it just runs traced effects.
- **Observability streams as reactive sources.** A DevTools/metrics protocol consumed as a `Stream` in a `Layer.effectDiscard`, folded into atoms, rendered by ordinary components. Observability data is just another atom input.

## 4. Progressive-loading choreography

A reusable service shape for boot sequences with progress UI: a `Loader` service exposing `withIndicator(message, minWaitTime)(effect)` that timestamps steps into a `loaderStepsAtom` (via the registry), enforces minimum display durations through a queue of delayed completions, and offers `finish` / `await`. Consumers wrap boot phases (`bootContainer.pipe(loader.withIndicator("Booting webcontainer"))`); the loading screen renders the atom; a derived `isLoadedAtom = runtime.atom(loader.await).pipe(Atom.map(AsyncResult.isSuccess))` serves consumers that only need the boolean. The pattern generalizes to any multi-phase startup.

## 5. Persistence and import chains

For "restore state from several possible sources" (share link → URL param → autosave → default):

- Each source is a small function of `get` returning `Option<T>` (effectful sources catch their errors, log a warning, and return `Option.none` so one broken source never masks the next).
- The import atom tries sources in priority order and logs which one won.
- Autosave: a background loop (`Effect.forever` + `forkScoped` in a mounted atom) that snapshots via a service, **skips writing when the snapshot equals the default or the initially-imported state** (so untouched imports don't pollute the save), and writes through an `Atom.kvs` with a full Schema.
- Share links: content-address the compressed payload server-side (hash of contents) so identical shares dedupe; reuse the same compressed encoding for downloads.

## 6. Known warts and honest caveats

So you can recognize them as debt rather than doctrine when you meet them in the wild:

- Framework-boundary `null as any` context defaults and `(..._: any)` third-party callback shims — violations of the no-`any` ideal, tolerated at the edges. Prefer a throwing accessor or non-null context creation helper where practical.
- The reference codebase ships no unit tests for its UI; the testing story for this architecture is `@effect/vitest` with `Layer`-swapped test services (see the effect-ts skill's testing guide) — services with explicit shapes (`Toaster`, no-op default) exist partly to make that swap trivial.
- No SSR hydration of atom state in the reference (its heavy features are client-only islands); if you need SSR, reach for `Hydration` + `useAtomInitialValues` rather than inventing serialization.
- Tracing in atom read functions is a per-project choice, not doctrine. The reference codebase uses `Effect.fnUntraced` there (hot paths, spans add noise), deliberately trading away tracing; other projects — including this monorepo, per `apps/frontend/AGENTS.md` — keep named `Effect.fn("Namespace.method")` spans everywhere. Follow the project convention, and in either regime keep named spans on service/business methods so you don't lose observability where it matters.
