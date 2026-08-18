# Discovery: add-todo-list

Date: 2026-08-17

## Coverage scan

| Category                   | Status  | Triage     | Note                                                                                                                                                     |
| -------------------------- | ------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Functional scope           | Partial | PRODUCT    | "A TODO feature" fixes add and check-off; everything past that was open. Settled by Q2 and Q3.                                                           |
| Domain model               | Missing | PRODUCT    | A task could be a line of text or a record with dates, notes and grouping. Settled by Q3.                                                                |
| Persistence                | Missing | PRODUCT    | Durability is user-visible and was unstated. Settled by Q1. The mechanism that delivers it is CONVENTION (below).                                        |
| Interaction & states       | Partial | DESIGN     | Empty state, the add box, and in-place rename affordances have no competing user-visible options worth a question. Assumed below, resolved in design.md. |
| Data operations            | Missing | PRODUCT    | Delete, rename, reorder and filter are each separately visible. Settled by Q2.                                                                           |
| Access & permissions       | Missing | CONVENTION | The app has no accounts and Q1 keeps the list on one device, so there is exactly one anonymous person and nothing to share.                              |
| Non-functional             | Partial | CONVENTION | Keyboard and screen-reader behavior comes from the vendored shadcn/Base UI primitives. Scale is assumed below.                                           |
| Integration points         | Partial | PRODUCT    | The app is a starter page today; whether that survives is visible on first load. Settled by Q4.                                                          |
| Migration of existing data | Clear   | -          | Nothing is stored today and there are no users, so there is nothing to carry over.                                                                       |
| Failure handling           | Partial | DESIGN     | The only failure available in a device-local feature is an unreadable saved list. Deferred.                                                              |
| Success criteria           | Partial | DESIGN     | No externally reported metric exists in this project. Assumed below.                                                                                     |

## Resolved by convention

| Question it would have been                              | Answer                                                                                                                                                                                                                                                               | Source                                                                               |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Where does the task list's state live — React or Atom?   | Atom. `useState` is only for ephemeral, view-local, consequence-free state; anything crossing a component boundary, async, or surviving unmount must be an `Atom`.                                                                                                   | `apps/frontend/AGENTS.md` § Effect and Atom                                          |
| How does state survive a page reload on the same device? | `Atom.kvs`. The scaffold names it as the deliberate choice for an atom that must outlive the registry's idle TTL — not a module-level `let`.                                                                                                                         | `apps/frontend/src/features/counter/atoms.ts`                                        |
| Do we build custom checkbox/text-input/button controls?  | No. shadcn components are preferred over custom wherever possible, and `checkbox`, `input` and `button` are already vendored.                                                                                                                                        | `apps/frontend/AGENTS.md` § shadcn, UI & styling; `apps/frontend/src/components/ui/` |
| How is a new page added?                                 | A component in `src/routes/`, a module-scope `const` for its element, and one `<Route>` line in `App.tsx` above the `path="*"` catch-all, which stays last.                                                                                                          | `apps/frontend/AGENTS.md` § Routing                                                  |
| Where does shared page chrome such as a nav go?          | `RootLayout` — a pathless layout route that exists as exactly this seam.                                                                                                                                                                                             | `apps/frontend/src/routes/RootLayout.tsx`                                            |
| How is a feature folder laid out?                        | `src/features/<name>/` with `atoms.ts`, `components/`, and an `index.ts` re-exporting both.                                                                                                                                                                          | `apps/frontend/src/features/counter/`                                                |
| What shape do the tests take?                            | `test/*.test.tsx` under happy-dom, `describe`/`it` from `@effect/vitest`, every query scoped with `within(container)`, a `RegistryProvider` mounted for absolute-value assertions, atom updates asserted inside `waitFor`, router hooks wrapped in `<MemoryRouter>`. | `apps/frontend/AGENTS.md` § Linting and tests                                        |
| How is a new dependency added, if one is needed?         | Edit the manifest and the `pnpm-workspace.yaml` catalog, then install. `pnpm add` and literal versions are both wrong.                                                                                                                                               | root `AGENTS.md` § Repo-wide rules                                                   |
| Is any of this state allowed in the query string?        | Only through `Atom.searchParam`, never `useSearchParams`. Not needed here, but it forecloses reaching for the router.                                                                                                                                                | `apps/frontend/AGENTS.md` § Effect and Atom                                          |

## Clarifications

### Q1. When someone adds a few tasks, closes the tab, and comes back tomorrow — what should they see?

**Answer:** Same list, same device

### Q2. Beyond typing a task in and checking it off, what should someone be able to do with it?

**Answer:** Delete a task (Recommended), Rename a task, Drag to reorder

### Q3. What does one task hold?

**Answer:** Just its wording (Recommended)

### Q4. Where should the task list live in the app?

**Answer:** Its own page, starter stays

## Deferred to design

- Which `KeyValueStore` layer backs `Atom.kvs`, and what the atom does with a saved value that no longer reads back as a task list.
- How a task is identified across renames and reorders, and how that identifier is generated.
- Whether manual order is carried by the position of items in a stored array or by an explicit rank on each task.
- How dragging is implemented and what its keyboard equivalent is — including whether it needs a dependency, which would mean a `pnpm-workspace.yaml` catalog entry rather than a literal version.
- Whether the feature exposes one atom holding the whole list or a per-task family, and where derived values such as the remaining count come from.
- How the nav renders in `RootLayout` — the vendored `navigation-menu` or plain styled links — without disturbing the `#root` flex shell that each route's top-level `<section>` sizes itself against.
- Whether `test/App.test.tsx` grows the new coverage or the feature gets its own test file.

## Assumptions

- ASSUMED: The list belongs to one person on one computer. Nobody else can see it, and there is nothing to share or invite anyone to.
- ASSUMED: A few hundred tasks is the most anyone will have, so there is no search, no paging, and no "load more".
- ASSUMED: With nothing in it, the page shows a short line inviting the first task rather than an empty area.
- ASSUMED: Tasks are added from a single text box — type and press Enter. Pressing Enter on an empty box adds nothing.
- ASSUMED: Deleting happens immediately. There is no "are you sure" and no undo, so a mistaken delete means retyping the task.
- ASSUMED: Renaming happens on the task's own row. Enter or clicking away keeps the new wording; Escape abandons it.
- ASSUMED: Finished tasks stay visible in the list with their box ticked, since hiding them was not chosen.
- ASSUMED: The only order is the one someone sets by hand. New tasks join the end of the list.
- ASSUMED: If the saved list cannot be read back, the page opens empty rather than showing an error. The person loses the old list without being told why.
- ASSUMED: The starter page and its click-counter are left exactly as they are, and a small nav appears at the top of both pages so someone can move between them. That nav is new work this change introduces.
- ASSUMED: The page lives at `/tasks`.
- ASSUMED: Everything on the page can be done with a keyboard alone and makes sense to a screen reader, to the standard the vendored shadcn controls already meet.
- ASSUMED: A week from now, success looks like: someone can add a task, tick it, rename it, drag it somewhere else, delete another, reload the page, and find the list exactly as they left it.

## Out of scope

- Signing in, accounts, and the same list on more than one device.
- Due dates, priorities, longer notes, subtasks, and several named lists.
- Hiding or filtering finished tasks, searching, and clearing all finished ones at once.
- Sharing a list with anyone or seeing anyone else's.
- Removing the starter page, its click-counter, or the `features/counter` reference slice.
