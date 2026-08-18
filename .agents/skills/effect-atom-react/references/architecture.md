# Application Architecture: Slices, Services, Client/Server, Islands

## Contents

1. Macro layout
2. Feature-slice anatomy and the dependency law
3. Services and layers: definition conventions
4. Scope tiers: what lives how long
5. Layer reuse via the shared MemoMap
6. Client/server features: shared contract, split implementations
7. Astro / island integration
8. Tooling posture

## 1. Macro layout

```
src/
  pages/          Routes; API routes under pages/api are thin Effect adapters
  components/     Shared UI primitives + shell components; islands only where needed
  features/       Vertical feature slices (the application lives here)
  services/       Cross-cutting app services with a client/server split
  hooks/          Truly generic React-only hooks (should stay nearly empty)
  lib/ data/ ...  Utilities, static data
```

The shell framework (Astro, Next, plain Vite) owns routing and static content; the application lives in feature slices that are framework-agnostic below the `components/` layer.

## 2. Feature-slice anatomy and the dependency law

```
features/<feature>/
  domain/       Pure model: Schema classes with methods, branded types
                (Brand.nominal), tagged errors, Data.taggedEnum UI states.
                No React, no services, no atoms.
  services/     Context.Service classes + layers. No React imports, ever.
  atoms/        Runtimes, families, fn atoms. Imports domain + services. No React.
  context/      Thin React-context bridges for stable handles (often one file).
  components/   React. Consumes atoms via hooks. Never imports from services/.
  index.tsx     Public entry (the island/root component).
```

Dependency direction is one-way: `domain ← services ← atoms ← components`. Enforce it in review; it is the rule that keeps every other pattern working. Folder names may drift per feature (`model/`, `runtime/`, `state/` are equivalent to `domain/`, `services/`, `atoms/`) — the layering is what matters, not the names.

Domain modeling specifics worth copying:

- `Schema.Class` / `Schema.TaggedClass` with instance methods (`workspace.pathTo(node)`, `file.withContent(c)`) — models carry behavior.
- Branded primitives for path-like strings: `type FullPath = Brand.Branded<string, "FullPath">`.
- `Schema.withDecodingDefaultKey` on optional fields so old persisted/shared payloads keep decoding as the schema evolves.
- UI modes as `Data.taggedEnum`, not boolean flags.
- Recursive structures via `Schema.suspend`.

## 3. Services and layers: definition conventions

Defer to the effect-ts skill for core service style; the conventions that matter for UI apps:

```ts
// Inferred shape from make (the common case)
export class WebContainer extends Context.Service<WebContainer>()("app/WebContainer", {
  make: Effect.gen(function* () { ...; return { ... } as const }),
}) {
  static readonly layer = Layer.effect(this, this.make).pipe(Layer.provide(Loader.layer))
}

// Explicit shape (when the contract is the point — swappable impls, no-op defaults)
export class Toaster extends Context.Service<Toaster, {
  readonly toast: (opts: { title: string; description: string }) => Effect.Effect<void>
}>()("app/Toaster", { make: Effect.succeed({ toast: () => Effect.void }) }) {
  static readonly layer = Layer.effect(this, this.make)
}
```

- Namespaced ids (`"app/Compression/Workspace"`); implementations returned `as const`; layers as **static members**, never hidden in namespaces.
- **Every exported layer pre-provides its own dependencies.** Consumers then compose flat `Layer.mergeAll(...)` lists at runtime boundaries without knowing transitive graphs. Use `Layer.provideMerge` when a dependency should also be visible to siblings.
- Layer constructor by need: `Layer.effect` (common), `Layer.succeed` (pure impls), `Layer.effectContext` (capture ambient context, e.g. to build a `runSync` usable in synchronous callbacks), `Layer.effectDiscard` (side-effect-only layers that provide no service — e.g. a layer that just forks a stream consumer).

### Services writing to atoms

Services participate in reactivity by requiring `AtomRegistry.AtomRegistry` (automatically available in `Atom.runtime` layers) and updating module-level atoms:

```ts
export const rootSpansAtom = Atom.make<ReadonlyArray<Span>>([])

export const DevToolsLayer = Layer.effectDiscard(
  Effect.gen(function* () {
    const registry = yield* AtomRegistry.AtomRegistry
    const container = yield* WebContainer
    yield* container.devTools.pipe(
      Stream.runForEach((event) => Effect.sync(() => registry.update(rootSpansAtom, fold(event)))),
      Effect.forkDetach,
    )
  }),
).pipe(Layer.provide(WebContainer.layer))
```

This is the sanctioned channel for background processes — stream consumers, file watchers, tracers, progress reporters — to drive UI. Components just render the atom. For the registry calls themselves, prefer the Effect-returning module functions (`Atom.set`, `Atom.update`, `Atom.get`, `Atom.getResult`, …) over wrapping `registry.*` in `Effect.sync` — they require `AtomRegistry` in the environment and compose like any other effect.

## 4. Scope tiers: what lives how long

- **Runtime-atom scope** (dominant): a layer given to `Atom.runtime` builds lazily on first dependent subscription and tears down when unused. Service finalizers and `forkScoped` fibers in `make` are tied to it. Guard non-reentrant global resources with a module-level `Semaphore` acquired/released in the same scope.
- **Handle scope** (per subsystem): a `createXHandle` effect runs inside the *calling atom's* scope, so mounts, watchers, and child processes die with the handle atom.
- **Call scope**: methods returning `Effect<A, E, Scope.Scope>` let the caller own the resource's lifetime (a `spawn` whose process dies with the terminal atom that called it).
- **Deliberate escapes**: `Effect.forkDetach` when a consumer must outlive its constructor's scope; `Effect.uninterruptible` around fibers that must complete (a progress feed); `Effect.cached` + `Scope.provide(effect, serviceScope)` to make a lazily-created engine belong to the service rather than its first caller. Comment every escape — they are exceptions.
- **Server scope**: build the handler layer once at module scope (`toWebHandler`) and tie `dispose()` to process signals.

## 5. Layer reuse via the shared MemoMap

All runtimes created with the module-level `Atom.runtime` factory share one `Layer.MemoMap` **per registry** (the factory's `memoMap` is itself an atom, so each `RegistryProvider` tree gets its own). Within a registry, layers are memoized by **reference identity**: a `WebContainer.layer` referenced by four different runtimes is built once and shared while any dependent atom is alive. Two laws follow:

1. Define each layer exactly once (hence `static readonly layer`).
2. Import that single value everywhere; never reconstruct an "equivalent" layer.

`Atom.runtime.addGlobalLayer(layer)` provisions something into every runtime made by that factory. `Atom.context()` creates a fresh factory when you genuinely need duplicate instances (rare); `Atom.context({ memoMap: Layer.makeMemoMapUnsafe() })` pins a concrete map shared across registries.

## 6. Client/server features: shared contract, split implementations

Anatomy for a feature with a server component (`src/services/<name>/`):

```
domain.ts       Shared Schema types and Schema.TaggedError errors (both sides)
rpc.ts          The contract: RpcGroup.make(Rpc.make("shorten", { payload, error, success }))
service.ts      Server implementation as a Context.Service (over KeyValueStore, DB, SDK...)
rpc-server.ts   Rpcs.toLayer(handlers).pipe(Layer.provide(Service.layer))
client.ts       Browser Context.Service: RpcClient.make(Rpcs) over
                RpcClient.layerProtocolHttp + FetchHttpClient.layer + RpcSerialization.layerJson
```

Client and server share *only* `domain.ts` + `rpc.ts`. Neither side contains an untyped fetch. The API route is a five-line adapter:

```ts
// pages/api/rpc.ts (Astro; same shape for Next route handlers)
const rpcRoute = RpcServer.layerHttp({ group: ShortenRpcs, path: "/api/rpc", protocol: "http" })
  .pipe(Layer.provide(ShortenLayer), Layer.provide(RpcSerialization.layerJson))
const { dispose, handler } = HttpRouter.toWebHandler(HttpRouter.layer.pipe(Layer.provideMerge(rpcRoute)))
process.on("SIGINT", () => dispose().then(() => process.exit(0), () => process.exit(1)))
export const POST: APIRoute = ({ request }) => handler(request)
```

For REST-shaped endpoints, the same split works with `HttpApi`/`HttpApiGroup`/`HttpApiEndpoint`/`HttpApiBuilder`. Server config comes from `Config.redacted`; server business logic uses named spans (`Effect.fn("Search.search")`).

For new API surfaces, prefer `AtomRpc.Service` / `AtomHttpApi.Service` on the client — they derive the client service *and* atom-based `query`/`mutation` helpers (with `timeToLive` caching and reactivity-key invalidation) directly from the contract, replacing the hand-written `client.ts` + fn atoms.

## 7. Astro / island integration

- React mounts as islands with the narrowest viable directive: `client:visible` for below-the-fold interactive content, `client:load` for nav/search, `client:only="react"` for inherently client-only apps (anything using browser-only resources like WebContainers).
- Pages hosting SharedArrayBuffer-dependent features must set COOP/COEP headers and `export const prerender = false`.
- Islands receive **data** (definitions, content) as props from Astro; they get **behavior and state** from atoms. Never serialize atoms or handles through island props.
- `useEffect` at the island boundary is legitimate glue for wiring `window`/custom events from the non-React shell (open/close events, keyboard shortcuts) and for mirroring local state into DOM attributes (scroll locks). That is the *only* sanctioned `useEffect` category.
- Two schema worlds coexist deliberately: the shell's content validation (Astro content collections use zod) versus application `Schema` everywhere data crosses runtime boundaries. Don't unify them.

## 8. Tooling posture

- Pin `effect` and all `@effect/*` packages to the **same version**; misalignment breaks at runtime in v4-beta.
- Deep namespaced imports (`import * as Effect from "effect/Effect"`), supported by `@effect/language-service` (`namespaceImportPackages`) loaded as a tsc plugin.
- Strictest TypeScript config; no `any`, no `as` casts in application code. Tolerated only at framework boundaries (context defaults, third-party callback shims) — and flag them as debt.
- One store: `@effect/atom-react` covers state, derived state, queries, mutations, persistence, and URL state. Adding Redux/Zustand/TanStack Query alongside reintroduces the multi-store synchronization problem this architecture exists to eliminate.
