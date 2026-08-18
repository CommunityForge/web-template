# Atom API Vocabulary (Effect v4)

Imports assumed throughout:

```ts
import * as Atom from "effect/unstable/reactivity/Atom"
import * as AtomRegistry from "effect/unstable/reactivity/AtomRegistry"
import * as AsyncResult from "effect/unstable/reactivity/AsyncResult"
import { useAtom, useAtomValue, useAtomSet, useAtomMount, useAtomSuspense } from "@effect/atom-react"
```

## Contents

1. Plain, derived, and writable atoms
2. External event sources
3. Effectful atoms and AsyncResult
4. Runtimes and layers
5. Function (command) atoms
6. Families
7. The `get` context (AtomContext)
8. DOM bridging
9. Persistence: kvs and searchParam
10. Lifecycle modifiers
11. React hooks
12. Adjacent modules worth knowing

## 1. Plain, derived, and writable atoms

```ts
// Mutable cell
export const searchQueryAtom = Atom.make("")

// Derived: reading is subscribing; no dependency arrays exist
export const soundEnabledAtom = Atom.make((get) => {
  const preference = get(soundPreferenceAtom)
  const unlocked = get(soundUnlockedAtom)
  if (!unlocked || preference === "off") return false
  if (preference === "on") return true
  return !get(prefersReducedMotionAtom)
})

// Single-input derivation
export const editorThemeAtom = themeAtom.pipe(
  Atom.map((theme) => (theme === "dark" ? "dracula" : "chrome-devtools")),
)

// Lens-like derived writable: read from two atoms, write to one
export const selectedSpanAtom = Atom.writable(
  (get): Span | undefined => get(rootSpansAtom)[get(selectedSpanIndexAtom)],
  (ctx, index: number) => ctx.set(selectedSpanIndexAtom, index),
)

// Time as a graph combinator — never setTimeout in a component
export const debouncedQueryAtom = searchQueryAtom.pipe(Atom.debounce(300))
```

Use `Data.taggedEnum` for UI-mode state so impossible states are unrepresentable:

```ts
export type State = Data.TaggedEnum<{
  Idle: {}
  Creating: { parent: Directory; type: FileType }
  Editing: { node: Directory | File }
}>
export const State = Data.taggedEnum<State>()
export const stateAtom = Atom.make<State>(State.Idle())
```

## 2. External event sources

Anything the platform pushes at you becomes a self-cleaning atom: setup, `get.setSelf` on events, `get.addFinalizer` for teardown. One subscription per registry, not per component instance.

```ts
export const themeAtom = Atom.make<"light" | "dark">((get) => {
  const observer = new MutationObserver(() => get.setSelf(getTheme()))
  get.addFinalizer(() => observer.disconnect())
  observer.observe(document.documentElement, { attributeFilter: ["class"] })
  return getTheme()
})
```

Same shape for `hashchange`, `matchMedia("(prefers-reduced-motion: reduce)")`, `ResizeObserver`, websocket messages, BroadcastChannel, visibility changes. Guard `typeof window === "undefined"` and return a default when the atom may be evaluated during SSR.

## 3. Effectful atoms and AsyncResult

When an atom's read function returns an `Effect` (or `Stream`), the atom's value type becomes `AsyncResult<A, E>` with **three** states — `Initial`, `Success`, `Failure` — each carrying a `waiting` flag. A refresh is therefore Success-with-`waiting: true` still holding the previous value, not a separate "Loading" state, which is why stale-while-refreshing UI is free. When a dependency changes, the registry **interrupts the in-flight effect** before starting the new one — stale-response races cannot happen. `Effect.tryPromise`'s `signal` argument gives you an AbortSignal for fetch.

```ts
export const searchResultsAtom = Atom.make((get) => {
  const query = get(debouncedQueryAtom)
  if (query.trim().length === 0) return Effect.succeed<ReadonlyArray<SearchResult>>([])
  return Effect.tryPromise({
    try: (signal) => fetch(`/api/search?query=${encodeURIComponent(query)}`, { signal }),
    catch: (cause) => new SearchError({ cause }),
  }).pipe(Effect.flatMap(decodeResponse))
})
```

Render from the states — never mirror them into `useState`:

```tsx
const result = useAtomValue(searchResultsAtom)
// result.waiting for spinners; AsyncResult.isFailure(result) for errors
// or explicit branching:
return AsyncResult.builder(result)
  .onSuccess((items) => <Results items={items} />)
  .onFailure((cause) => <ErrorView cause={cause} />)
  .render()
// .onError / .onErrorTag narrow typed errors; .exhaustive() replaces .render()
// and type-errors until every reachable case is handled.
```

For query-library cache semantics, pipe the atom through `Atom.swr({ staleTime, revalidateOnMount?, revalidateOnFocus? })` — reads within `staleTime` skip revalidation, manual `refresh` always forces. `Atom.refreshOnWindowFocus` (built on `Atom.windowFocusSignal`) is the standalone refetch-on-focus modifier.

## 4. Runtimes and layers

`Atom.runtime(layer)` creates an atom whose value is a built runtime for that layer. The layer builds lazily on first dependent subscription and tears down when unused. **All runtimes from the default factory share a per-registry `Layer.MemoMap`** (the factory's `memoMap` is itself an atom), so layers are memoized by reference identity across runtimes within a registry: define each layer exactly once (`static readonly layer` on the service class), import that single value everywhere, and a service shared by several runtimes is constructed once. Constructing an "equivalent" layer twice double-builds the service — treat layer identity as sacred. (Two `RegistryProvider` trees get independent memoization; pass a concrete map via `Atom.context({ memoMap: Layer.makeMemoMapUnsafe() })` if you genuinely need sharing across registries.)

```ts
const runtime = Atom.runtime(
  Layer.mergeAll(Loader.layer, Terminal.layer, Toaster.layer, WebContainer.layer),
)

// Scoped effectful value with services; value is AsyncResult
export const handleAtom = runtime.atom(
  Effect.fnUntraced(function* (get) {
    const container = yield* WebContainer
    ...
  }),
)
```

Keep an expensive runtime alive across brief unmounts (tab switches, StrictMode double-mounts):

```ts
const editorRuntime = Atom.runtime(Layer.mergeAll(Monaco.layer, Loader.layer)).pipe(
  Atom.setIdleTTL("10 seconds"),
)
```

Every layer given to `Atom.runtime` automatically has the `AtomRegistry.AtomRegistry` service available, which is how services write to atoms (see §7 of the patterns reference).

## 5. Function (command) atoms

Commands are atoms you *call*. Value = `AsyncResult` of the last invocation; input and errors are typed; invoke via `useAtomSet`.

```ts
export const copyLinkAtom = Atom.fn<WorkspaceHandle>()(
  Effect.fnUntraced(function* (handle, get) {
    const { url } = yield* get.result(shareAtom(handle))   // await another atom's result
    navigator.clipboard.writeText(url)
    // Self-resetting UI state: back to Initial after 2s, scoped to this atom
    yield* Effect.sleep(2000).pipe(
      Effect.tap(() => Effect.sync(() => get.setSelf(AsyncResult.initial()))),
      Effect.forkScoped,
    )
  }),
)
```

- `runtime.fn<Args>()(...)` when the command needs services; it also takes `reactivityKeys` so a successful run invalidates query atoms watching those keys (see `Reactivity`, §12).
- Pass `{ concurrent: true }` when invocations may overlap (otherwise a new call interrupts the previous); `{ initialValue }` seeds the pre-first-call state.
- Put post-mutation bookkeeping inside the command with `get.set` — e.g., after `createFile`, select the new file; after `removeFile`, fix a dangling selection. Cohesion lives with the mutation, not scattered in components.
- `Atom.fnSync` for synchronous commands (e.g., history manipulation + a few `get.set`s).
- `useAtomSet(atom, { mode: "promise" })` lets a call site await the result when needed (`"promiseExit"` to receive the `Exit` instead of throwing).
- Writing the `Atom.Reset` symbol to a fn atom returns it to `Initial`; writing `Atom.Interrupt` cancels the in-flight run — the packaged alternatives to hand-rolled `get.setSelf(AsyncResult.initial())`.

## 6. Families

```ts
export const stepStateAtom = Atom.family((step: StepDefinition) =>
  Atom.make<VisualEffectState>(InitialState),
)
```

Memoized by structural `Equal` on the argument; entries held by `WeakRef` + `FinalizationRegistry` so unused members are GC'd. The returned atom is referentially stable for equal arguments, which makes calling a family **during render** pure and safe (`useAtomValue(stepStateAtom(step))`). Use families for all per-entity state; never lift a `Map<id, State>` into a parent component. Families may return not just atoms but objects bundling several (an element atom + an effect atom, for instance).

## 7. The `get` context (AtomContext)

The read/write context is a complete bridge into the effect system. The important members:

| Member | Meaning |
| --- | --- |
| `get(atom)` | Reactive read: value + dependency registration |
| `get.once(atom)` | Snapshot read, intentionally non-reactive (the visible replacement for "omit from deps") |
| `get.some(optionAtom)` | `Effect` that suspends until the Option is Some — the DOM-awaiting primitive (`someOnce` for a non-reactive variant) |
| `get.result(asyncAtom)` | Await another atom's `AsyncResult` as an `Effect<A, E>`; `{ suspendOnWaiting: true }` also waits out refreshes; `resultOnce` for a snapshot |
| `get.stream(atom)` / `get.streamResult(asyncAtom)` | Consume an atom as a `Stream` (drive pipelines from state changes); `streamResult` unwraps `AsyncResult` into `Stream<A, E>` |
| `get.subscribe(atom, f, { immediate })` | Imperative subscription with automatic cleanup |
| `get.set / get.setSelf / get.refresh / get.refreshSelf` | Writes and invalidation (`get.setResult` writes into an AsyncResult-typed writable and awaits it) |
| `get.self()` | This atom's own current value as an `Option` |
| `get.addFinalizer(f)` | Cleanup tied to this atom's lifetime |
| `get.mount(atom)` | Keep another atom alive from inside this one |
| `get.registry` | Escape hatch to the registry itself |

The `get` inside `Atom.fn` bodies is the narrower `FnContext`: same members minus `once`/`refreshSelf` — a command runs per invocation rather than reactively, so a bare `get(atom)` there is already just a read, not a subscription.

Effect-land mirrors of the registry operations also exist as module functions — `Atom.get/set/update/modify/getResult/refresh/mount` return `Effect`s requiring the `AtomRegistry` service. Inside services, prefer these over threading `registry.*` calls through `Effect.sync`.

Streams from state — a full sync loop scoped to the atom:

```ts
yield* get.stream(handle.selectedFile).pipe(
  Stream.switchMap((file) => syncFileToEditor(file)),   // switchMap cancels the old file's sync
  Stream.runDrain,
  Effect.retry(Schedule.spaced("200 millis")),
  Effect.forkScoped,                                    // dies with the atom
)
```

## 8. DOM bridging

The pattern for mounting imperative libraries (Monaco, xterm, maps, charts) into React-owned DOM:

```ts
// atoms
const element = Atom.make(Option.none<HTMLElement>())
const editor = runtime.atom(
  Effect.fnUntraced(function* (get) {
    const el = yield* get.some(element)      // suspends until the ref fires
    const editor = yield* createEditor(el)   // acquireRelease inside the service
    get.subscribe(themeAtom, (t) => editor.updateOptions({ theme: t }), { immediate: true })
    return editor
  }),
)
```

```tsx
// component
const setElement = useAtomSet(element)
const ref = useCallback((node: HTMLElement | null) => {
  if (node) setElement(Option.some(node))
}, [setElement])
useAtomMount(editor)
return <div ref={ref} className="h-full" />
```

DOM availability becomes an awaited value inside a cancellable, scoped effect. No ref-ordering puzzles, no re-init on remount (combine with `setIdleTTL`), and disposal is the scope's job.

## 9. Persistence: kvs and searchParam

```ts
import * as KeyValueStore from "effect/unstable/persistence/KeyValueStore"

const kvsRuntime = Atom.runtime(KeyValueStore.layerStorage(() => localStorage))

export const autoSaveWorkspaceAtom = Atom.kvs({
  runtime: kvsRuntime,                  // any runtime providing KeyValueStore
  key: "workspace-autosave",
  schema: Schema.Option(Workspace),     // full schema validation at the boundary
  defaultValue: Option.none,            // LazyArg — a thunk, evaluated on demand
})

export const codeAtom = Atom.searchParam("code", {
  schema: Schema.StringFromBase64Url.pipe(Schema.check(Schema.isNonEmpty())),
})
```

Persisted and URL state is declarative, validated, and reactive. Use `Schema.withDecodingDefaultKey` on domain schemas to keep old persisted payloads decodable as the model evolves. Details that matter: `Atom.kvs` defaults to a synchronous value type (pass `mode: "async"` to get `AsyncResult` and support async stores); `Atom.searchParam` without a schema yields a plain `string`, with a schema it yields `Option<A>` (decode failure → `Option.none`), the schema must be synchronous and context-free, and writes are debounced (~500 ms) into a single `history.pushState`.

## 10. Lifecycle modifiers

- `Atom.keepAlive` — pin an atom for the registry's lifetime (rare; for app-global subscriptions).
- `Atom.setIdleTTL(duration)` — survive remount gaps; the cache policy for expensive resources.
- `Atom.withLabel("feature:name")` — name atoms for debugging/devtools.
- The **default** (no-provider) registry has a 400 ms `defaultIdleTTL`, so unsubscribed atoms linger just long enough to survive StrictMode double-mounts. A `RegistryProvider` you mount yourself has **no** default TTL unless you pass `defaultIdleTTL` — atoms without their own TTL are then disposed the moment their last subscriber leaves. If state vanishing on unmount surprises you, that is the prompt to decide deliberately between family+TTL, `keepAlive`, or `Atom.kvs`.

## 11. React hooks

| Hook | Use |
| --- | --- |
| `useAtomValue(atom)` / `useAtomValue(atom, selector)` | Read; selector narrows re-renders to the slice |
| `useAtom(atom)` | `[value, set]` for writables |
| `useAtomSet(atom)` | Setter/invoker only (no re-render on value change); mounts the atom; `mode: "promise"` to await, `"promiseExit"` for the `Exit`; default mode also accepts an updater `(current) => next` |
| `useAtomMount(atom)` | Keep a background atom alive (editor, sync loop, autosave) without reading |
| `useAtomSuspense(atom, opts?)` | Suspense-integrated await of an `AsyncResult` atom; returns the `Success` object (read `.value`) |
| `useAtomRefresh(atom)` | Imperative invalidation |
| `useAtomSubscribe(atom, f, opts?)` | Run a callback on changes without reading during render |
| `useAtomRef(ref)` / `useAtomRefProp(ref, key)` | Subscribe to an `AtomRef` (mutable reference with property lenses) |

Sharp edges worth knowing:

- **Selectors must be referentially stable** (module-level functions, not inline arrows): `useAtomValue(atom, f)` memoizes `Atom.map(atom, f)` on `[atom, f]`, so a fresh closure every render tears down and rebuilds the subscription every render.
- `useAtomSuspense` suspends only while `Initial` (pass `suspendOnWaiting: true` to also suspend on refreshes) and **throws failures** (`Cause.squash`) — wrap consumers in an error boundary, or pass `includeFailure: true` and branch on the returned result yourself.
- The registry batches notifications through React's scheduler at low priority, so update bursts coalesce — in tests, assert atom-driven UI changes inside `waitFor`.
- Provide a registry explicitly (`RegistryProvider`) when you need isolation (tests!) or SSR seeding; the default context registry is module-scope and shared. The provider builds its registry once (later prop changes are ignored) and disposes it ~500 ms after unmount, canceled on quick remounts.

## 12. Adjacent modules worth knowing

- `AtomRpc.Service` / `AtomHttpApi.Service` — class factories (same two-stage shape as `Context.Service`) deriving a typed client service from an `RpcGroup`/`HttpApi`. The class exposes `.runtime`, `.query(tag, payload, { timeToLive?, reactivityKeys? })` returning an `AsyncResult` atom (a `PullResult` writable for stream RPCs), and `.mutation(tag)` returning a fn atom whose argument carries `payload` and optional `reactivityKeys`. Prefer these over hand-rolling client services + fn atoms for new API surfaces.
- `Reactivity` — key-based invalidation service; `Atom.withReactivity(keys)` (also on each runtime factory) refreshes atoms when keys invalidate, and fn atoms' `reactivityKeys` option invalidates on success — the packaged cache-invalidation story for mutations.
- `Hydration` (`dehydrate`/`hydrate`) + `useAtomInitialValues` / `HydrationBoundary` — SSR dehydration/rehydration of atom values (atoms opt in via `Atom.serializable`).
- `Atom.optimistic` / `Atom.optimisticFn` — optimistic updates; `Atom.pull` — pagination/streaming pulls; `Atom.withFallback` — fallback atoms while a primary is Initial; `Atom.batch(() => ...)` — coalesce multiple writes into one notification wave.
- `ScopedAtom.make` — the `@effect/atom-react` top-level `make` export (beware in autocomplete: it is not `Atom.make`): wraps an atom factory in a `{ Provider, Context, use }` trio, creating the atom once per provider subtree — the packaged "stable handle in context".
- `@effect/atom-react` has Solid and Vue siblings; the hook layer is thin and the atom layer is framework-agnostic.
