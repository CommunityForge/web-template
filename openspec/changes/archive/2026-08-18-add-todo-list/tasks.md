## 1. Domain model and pure transforms

Everything here is plain functions and `.tsx` test files, no React and no registry. Most of the
`task-list` scenarios are settled in this group.

- [x] 1.1 Add `apps/frontend/src/features/task-list/task.ts` with the `Task` schema (`id`, `text`,
      `done`) and a module-local id generator wrapping `crypto.randomUUID`. Add
      `apps/frontend/test/task.test.tsx` (`.tsx`, not `.ts` — see design D9) asserting a freshly made
      task carries its wording and is not done, and that two tasks get different ids.
- [x] 1.2 `addTask`: appends to the end, trims surrounding whitespace, and returns the list unchanged
      for empty or whitespace-only input. Tests: a task is added; a second task lands below the first;
      an empty entry adds nothing.
- [x] 1.3 `toggleTask`: flips `done` for one id, leaving wording and position alone. Tests: ticking;
      unticking; a ticked task is still in the same position.
- [x] 1.4 `renameTask`: replaces wording for one id, keeping `done` and position; returns the list
      unchanged when the new wording is empty or whitespace-only. Tests for all three.
- [x] 1.5 `removeTask`: drops one id, the rest keeping their relative order. Test with a
      three-task list.
- [x] 1.6 `moveTask`: moves one id up or down a single position, other tasks closing the gap in their
      existing relative order; a no-op at either end. Tests for a move to the top, a move down, and
      both no-ops.

## 2. The durable list

- [x] 2.1 Add `apps/frontend/src/features/task-list/atoms.ts`: a module-scope
      `Atom.runtime(KeyValueStore.layerStorage(() => localStorage))` and an `Atom.kvs` keyed
      `task-list:tasks` with an `Array(Task)` schema and `defaultValue: () => []`, left in sync mode.
      Put its tests in their own file, `apps/frontend/test/task-list-storage.test.tsx` — one
      `localStorage` key shared by concurrent tests is why this is not folded into another file
      (design D9). Assert: a list written through the atom reads back after remounting against a fresh
      `RegistryProvider`; and with nothing saved, the atom is the empty list.
- [x] 2.2 In that same file, assert that a saved value which no longer decodes leaves the atom as the
      empty list, with nothing thrown and the list still writable afterwards.
- [x] 2.3 Confirm `crypto.randomUUID` is available under happy-dom while running 1.1's test. If it is
      not, replace the generator's body — the wrapper from 1.1 is the only place that changes.

## 3. The task list itself

Components use the already-vendored `input`, `checkbox` and `button`. Scope every query with
`within(container)`, mount a `RegistryProvider` for absolute-value assertions, and wrap atom updates
in `waitFor`.

- [x] 3.1 `AddTaskForm`: one text box, Enter adds through `setTasks(addTask(...))`, and the box is
      empty and ready afterwards. Test that pressing Enter on an empty box adds nothing and shows no
      error message.
- [x] 3.2 `TaskRow`: the vendored checkbox for done, the wording, and a delete action that takes effect
      on the first click with no confirmation step. Test that a ticked row stays in place and readable,
      and that after a delete nothing on the page offers to restore the task.
- [x] 3.3 In-place renaming on the row: Enter keeps the new wording, clicking away keeps it, Escape
      restores the previous wording, and confirming an emptied box keeps the previous wording. One test
      per path.
- [x] 3.4 `TaskList`: renders rows in stored order, and the empty state — a short line inviting the
      first task with the add box present. Test it on a first visit and again after deleting the only
      remaining task.
- [x] 3.5 Move up and Move down actions on each row, wired to `moveTask`, plus a polite live region
      naming where the moved task landed. Test a keyboard-only move and the announcement.
- [x] 3.6 HTML5 dragging on rows — `draggable` with `dragstart`/`dragover`/`drop` — reordering through
      the same `moveTask` path as 3.5. Test dragging the third task to the top.
- [x] 3.7 Accessibility test: the add box and, for every task, its tick, its wording, its delete, and
      its two move actions are all reachable by keyboard; each task announces its wording and whether
      it is done.
- [x] 3.8 Test that the page offers nothing to sign in to, nothing to share, and no other person's
      tasks.
- [x] 3.9 Add `apps/frontend/src/features/task-list/index.ts` re-exporting the components and the atom,
      matching `features/counter/index.ts`.

## 4. The page and its route

- [x] 4.1 Add `apps/frontend/src/routes/Tasks.tsx` rendering the list inside a top-level `<section>`
      that sizes itself as a direct flex child of the `#root` shell.
- [x] 4.2 In `apps/frontend/src/App.tsx`, add a hoisted `const TASKS = <Tasks />` and one
      `<Route path="tasks" element={TASKS} />` inside the layout route, above the `path="*"` catch-all.
      Test with `<MemoryRouter>` and a module-scope `initialEntries` that `/tasks` renders the page.

## 5. Shared navigation

- [x] 5.1 Rewrite `apps/frontend/src/routes/RootLayout.tsx` to return a fragment holding a `<nav>` and
      the `<Outlet/>`, with `NavLink`s to `/` and `/tasks` and their `className` function hoisted to
      module scope. Update the comment, which currently states the layout is deliberately empty.
- [x] 5.2 Test moving from the starter page to the task list and back, and that the link for the
      current page is marked distinguishably from the other.
- [x] 5.3 Test that an unrecognized address still shows the not-found page and that the nav is present
      on it, putting both real pages one step away.
- [x] 5.4 Test that the nav's links come before the page's own content in keyboard order, and that it
      is announced as the app's navigation with the current page identified.
- [x] 5.5 Run the existing `apps/frontend/test/App.test.tsx` unchanged as the starter-page regression
      check: the `Get started` heading, the click-counter, and the not-found route all behave as
      before, now with the nav above them. If any assertion needs editing to pass, treat that as a
      finding about 5.1 rather than a test to adjust.

## 6. Verification

- [x] 6.1 `pnpm check`, `pnpm test`, and `pnpm --filter=frontend lint` (the type-aware pass; plain
      `pnpm lint` skips it) all clean.
- [x] 6.2 `nix fmt` and `nix flake check` clean — the latter runs `typos` with `en-us`, so British
      spellings in new code or comments fail here.
- [x] 6.3 `nix build .#frontend` clean. No dependency was added, so `frontend.nix`'s `hash` should not
      need refreshing; if the build reports `ERR_PNPM_NO_OFFLINE_TARBALL`, something did get added and
      the hash needs the `pkgs.lib.fakeHash` round trip.
