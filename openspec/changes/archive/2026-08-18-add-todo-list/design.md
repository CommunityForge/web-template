## Context

See `proposal.md` § Why for motivation and `discovery.md` for the answers this design is built on.
The constraints that actually shape the approach:

- `apps/frontend` is a bundler-built leaf. There is no server, no data layer, and nothing in
  `openspec/specs/` yet.
- `features/counter/` is the only existing slice and sets the shape: `atoms.ts`, `components/`,
  `index.ts` re-exporting both. Its own comment names `Atom.kvs` as the deliberate choice for state
  that must outlive the registry's 400 ms idle TTL.
- `RootLayout` is a bare `<Outlet/>` whose comment declares it the seam for exactly the nav this
  change adds — and forbids a wrapper _element_, because `#root` is the `flex min-h-svh flex-col`
  shell each route's top-level `<section>` sizes itself against.
- `input`, `checkbox`, `button` and `navigation-menu` are already vendored under
  `src/components/ui/`.

**Prior art, superseded.** An untracked change `add-todo-page` sits in the worktree
`.claude/worktrees/add-todo-page-353a7f/openspec/changes/`, planned under the older `spec-driven`
schema before the guided one landed. It scoped an in-memory-only list at `/todos` with add, toggle
and remove — no durability, no rename, no reordering, all of which discovery has since settled the
other way. It is not visible to `openspec` from the repo root and should be treated as replaced by
this change, not merged with it.

## Goals / Non-Goals

**Goals:**

- One durable source of truth for the list, mutated only through a single writable atom.
- Most spec scenarios testable as pure functions, without rendering React or touching the registry.
- Reordering by keyboard as a first-class path rather than a fallback bolted onto dragging.
- No new runtime dependency, so no catalog entry and no `frontend.nix` hash churn.

**Non-Goals:**

- A service layer. The feature's only I/O is the key-value store, which `Atom.kvs` already wraps —
  a `Context.Service` in front of it would be indirection with nothing behind it.
- Any abstraction that anticipates a server, an account, or a second list. Discovery ruled all three
  out of scope; designing a seam for them now costs more than adding one later.
- Touching `features/counter/`, `routes/Home.tsx`, or `routes/NotFound.tsx`.

## Decisions

### D1. The list is one `Atom.kvs` over `localStorage`

`Atom.runtime(KeyValueStore.layerStorage(() => localStorage))` at module scope in the slice, feeding
`Atom.kvs({ runtime, key: "task-list:tasks", schema, defaultValue: () => [] })`. Left in the default
sync mode, so the atom's value is `Array<Task>` directly rather than an `AsyncResult` every component
has to unwrap. The key mirrors the counter's `Atom.withLabel("counter:count")` naming.

- _`Atom.make` + `Atom.keepAlive`_ — rejected: survives unmount but not a reload, which is the
  requirement.
- _Hand-rolled `localStorage` reads and writes inside an effect_ — rejected: re-implements `Atom.kvs`
  and loses schema validation at the boundary.

### D2. An unreadable saved value needs no bespoke handling

`Atom.kvs` in sync mode ignores any non-success decode result and falls back to `defaultValue`
(`node_modules/effect/src/unstable/reactivity/Atom.ts`, the `kvs` subscribe callback returns early
unless the result is a success). The "saved list cannot be read back" scenario is therefore satisfied
by construction: the page opens empty and stays usable.

One nuance to be aware of rather than fix: the undecodable string stays in `localStorage` until the
first write overwrites it. That is harmless precisely because it can never decode into anything
visible. Any field added to `Task` later must use `Schema.withDecodingDefaultKey`, or every existing
list on every device silently decodes to empty through this same path.

### D3. `Task` is `{ id, text, done }`, with `id` from `crypto.randomUUID()`

- _Array index as identity_ — rejected: reordering plus in-place renaming makes an index-keyed row
  unstable, and React will carry an open edit box onto the wrong task.
- _A saved incrementing counter_ — rejected: a second piece of stored state to keep consistent, for
  no benefit over a random id.

Ids are generated behind one module-local function so that if `crypto.randomUUID` turns out to be
unavailable under happy-dom, the fallback is a single edit rather than a sweep.

### D4. Order is the position of items in the stored array

An explicit rank or fractional index earns its keep when several writers reorder concurrently. There
is one device and one writer, so the array's own order is the order, and moving a task is a splice.

### D5. One atom holding the whole list, plus pure transforms

Every mutation is a pure `Array<Task> => Array<Task>` transform — `addTask`, `toggleTask`,
`renameTask`, `removeTask`, `moveTask` — living in `task.ts` beside the `Task` schema. Components
only wire an event to `setTasks(transform)`, exactly as `Counter` does with
`setCount((previous) => previous + 1)`.

- _An `Atom.family` per task_ — rejected: every write has to land in the one stored value anyway, so
  a family adds a coordinating write and buys nothing.

The payoff is testing: adding, ticking, renaming, deleting, reordering, the blank-entry rule and the
blank-rename rule are all assertions on plain functions. Only durability, keyboard reach and screen
reader output need a rendered tree.

### D6. Native drag, with Move up / Move down buttons as the keyboard path

Rows are `draggable` and use the HTML5 `dragstart`/`dragover`/`drop` events. Each row also carries
explicit Move up and Move down actions, and a polite live region announces where a moved task landed.

- _A drag-and-drop library (dnd-kit, pragmatic-drag-and-drop)_ — rejected: it would be the app's
  first non-vendored feature dependency, which means a `pnpm-workspace.yaml` catalog entry, a
  `catalog:` reference in `apps/frontend/package.json`, and a `frontend.nix` `hash` refresh through
  `pkgs.lib.fakeHash` — plus a library to keep current, for one list of at most a few hundred rows.
- _A hand-rolled pointer-events drag_ — rejected: as much work as the library with none of its
  keyboard support.

The buttons are not a consolation prize. The spec requires reordering without a pointing device
either way, and buttons are assertable with a single `fireEvent.click`, where a library's keyboard
sensor needs a key sequence that happy-dom may or may not deliver faithfully.

Trade-off: HTML5 drag does not fire on touch, so on a phone the buttons are the only way to reorder.
Acceptable because they are the primary path, not a degraded one.

### D7. The nav is `NavLink`s in `RootLayout`, returned as a fragment

`RootLayout` returns a fragment containing a `<nav>` and the `<Outlet/>`. Its comment forbids a
wrapper _element_ so that route content stays a direct flex child of `#root`; a fragment preserves
that, and both the nav and the route's `<section>` remain direct children. The comment must be
updated — it currently states the layout is deliberately empty, which stops being true.

- _The vendored `navigation-menu`_ — rejected: Base UI machinery for menus with popups and submenus,
  aimed at a problem two links do not have.

`NavLink` is chosen over `Link` because it exposes `isActive`, which is precisely the "current page is
identifiable" requirement, and it is available in declarative mode. Its `className` accepts a
function, and `react-perf/jsx-no-new-function-as-prop` is an error repo-wide — so that function is
hoisted to module scope, the same fix the route element `const`s in `App.tsx` already use.

### D8. Files and routing

- `src/routes/Tasks.tsx` — the page.
- `src/features/task-list/task.ts` — the `Task` schema and the pure transforms.
- `src/features/task-list/atoms.ts` — the runtime and the `Atom.kvs`.
- `src/features/task-list/components/` — the list, a row, and the add form.
- `src/features/task-list/index.ts` — barrel, per the counter slice.
- `src/App.tsx` — a hoisted `const TASKS = <Tasks />` and one `<Route path="tasks" element={TASKS} />`
  inside the layout route, above the `path="*"` catch-all. No leading slash: nested under the pathless
  layout route it resolves to `/tasks`.

### D9. Every new test file is `.tsx`, including the pure-transform one

Root `tsconfig.tests.json` globs `apps/*/test/**/*.ts` only, so a `.ts` test here would be owned by
both that project and this unit's `tsconfig.app.json`. `apps/frontend/AGENTS.md` calls this out; it
applies to the transform tests even though they render nothing.

Durability assertions go in their own test file. `sequence.concurrent` is on and every test in a file
shares one `localStorage` key through one module-scope atom, so reload-style assertions interleaved
with other tests in the same file would race each other regardless of which `RegistryProvider` they
mount. Splitting the file is cheaper than serializing one.

The existing `test/App.test.tsx` renders `App` at `/`, which now also mounts the nav. Its assertions
are scoped with `within(container)` and target the heading, the counter and the not-found page, so
they should continue to pass unchanged — but they are the regression check for
`app-navigation`'s "starter page keeps working" requirement and must be run, not assumed.

## Existing files this change touches

| File                                                          | Read / Modified / Replaced                                       |
| ------------------------------------------------------------- | ---------------------------------------------------------------- |
| `apps/frontend/src/App.tsx`                                   | Modified — one element `const`, one `<Route>`                    |
| `apps/frontend/src/routes/RootLayout.tsx`                     | Modified — fragment with a `<nav>`; comment updated              |
| `apps/frontend/test/App.test.tsx`                             | Read, and re-run as the starter-page regression check            |
| `apps/frontend/src/features/counter/`                         | Read only — the slice shape this feature copies                  |
| `apps/frontend/src/components/ui/{input,checkbox,button}.tsx` | Read only — consumed as-is                                       |
| `apps/frontend/index.html`                                    | Read only — the `#root` flex shell constrains D7                 |
| `apps/frontend/frontend.nix`                                  | Untouched — `extraSrcs` already takes `./src` and `./test` whole |

## Risks / Trade-offs

- **Concurrent tests share one `localStorage` key** → durability assertions live in a dedicated test
  file; everything else is asserted against pure transforms.
- **This project's Vitest + happy-dom setup never exposes a global `localStorage`.** Node ≥ 22
  defines its own global `localStorage` (undefined unless `--localstorage-file` is passed), and
  Vitest's built-in happy-dom environment integration does not populate one either — its
  `populateGlobal` key list (`vitest/dist/chunks/index.*.js`) omits `localStorage`/`sessionStorage`,
  and the property is defined via a getter on happy-dom's `Window` prototype rather than as an own
  property `Object.getOwnPropertyNames` would pick up. `atoms.ts` therefore reads
  `window.localStorage` (not bare `localStorage`) to match real-browser semantics, and every test
  file that mounts the real `tasksAtom` (`task-list-storage.test.tsx`, `Tasks.test.tsx`,
  `nav.test.tsx`) installs a small in-memory `Storage` stand-in behind
  `if (typeof window.localStorage === "undefined")`, so real browsers are unaffected. This is
  discovered-during-implementation, not assumed above; the same shim already exists, independently
  validated, in `.agents/skills/effect-atom-react-workspace`'s eval fixtures.
- **HTML5 drag does not fire on touch** → Move up / Move down are the universal path and the one the
  spec requires; drag is the enhancement.
- **`crypto.randomUUID` may not exist under happy-dom** → id generation sits behind one module-local
  function, so a fallback is a one-line change. Confirm in the first test that adds a task.
- **`RootLayout`'s comment currently forbids a wrapper** → a fragment satisfies it, but the comment
  must be rewritten or the next reader will believe the nav violates it.
- **`NavLink`'s function `className` trips `react-perf/jsx-no-new-function-as-prop`** → hoist it to
  module scope.
- **A future field on `Task` can silently wipe every saved list** → `Schema.withDecodingDefaultKey`
  on anything added, per D2.
- **Two plans for the same feature exist** → the worktree's `add-todo-page` artifacts are superseded;
  implementing both would leave the app with two todo pages.

## Migration Plan

Nothing is stored today and there are no users, so there is nothing to carry over. Rolling back means
removing the `<Route>` line, the nav, and the feature folder; the `task-list:tasks` key is left
orphaned in whichever browsers had it, which is inert.
