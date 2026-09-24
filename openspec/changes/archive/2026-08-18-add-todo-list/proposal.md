## Why

`apps/frontend` has no way to keep track of anything. It ships a starter page and a click-counter,
so a person can open it and read about Vite but cannot record a single thing they need to do. This
change gives the app its first thing someone would actually come back to, and in doing so exercises
the parts of the stack that are currently only asserted by scaffold: Atom-owned state, state that
outlives a reload, the vendored shadcn controls, a second route, and tests against all of it.

## What Changes

- **New page at `/tasks`** holding a single list of things to do. Someone types a task into one text
  box and presses Enter to add it; new tasks join the end of the list.
- **Ticking a task off** marks it done in place. Finished tasks stay in the list with their box
  ticked — they are not hidden or moved.
- **Renaming a task** happens on its own row. Enter or clicking away keeps the new wording; Escape
  abandons it.
- **Deleting a task** removes it immediately, with no confirmation step and no undo.
- **Reordering by dragging** lets someone put the list in whatever order they want, with a
  keyboard-only equivalent so the feature is not mouse-only.
- **The list survives closing the browser.** Reopening the app on the same computer shows the list
  exactly as it was left — same tasks, same ticks, same order.
- **A nav appears at the top of every page**, linking the starter page and the task list, so both are
  reachable. This is new chrome on a page that previously had none, and is the only visible change to
  the starter page.
- **The starter page, its click-counter, and `features/counter` stay exactly as they are.** This
  change adds a page beside them rather than replacing them.

No breaking changes: nothing here exists today, and nothing existing changes behavior. The nav is
additive.

## Capabilities

### New Capabilities

- `task-list`: keeping a personal list of things to do — adding, ticking off, renaming, reordering
  and deleting tasks, and finding the list unchanged after coming back to the app on the same device.
- `app-navigation`: moving between the app's pages, and what happens at a path the app does not
  recognize.

### Modified Capabilities

None. `openspec/specs/` is empty, so this change establishes the project's first capabilities and
their flat kebab-case organization.

## Impact

**New code**

- `apps/frontend/src/features/task-list/` — the feature slice, following `features/counter/`'s shape
  (`atoms.ts`, `components/`, `index.ts`).
- `apps/frontend/src/routes/Tasks.tsx` — the page.
- Tests under `apps/frontend/test/`.

**Modified code**

- `apps/frontend/src/App.tsx` — one hoisted element `const` and one `<Route>` line, above the
  `path="*"` catch-all.
- `apps/frontend/src/routes/RootLayout.tsx` — currently a bare `<Outlet/>` documented as the seam for
  exactly this nav. It must keep sizing correctly against the `flex min-h-svh flex-col` `#root` shell
  declared in `index.html`.

**Dependencies**

- Reuses the already-vendored `input`, `checkbox` and `button` shadcn components, and the vendored
  `navigation-menu` if the nav wants it.
- Dragging may require a new dependency. If it does, it goes in as a `catalog:` entry in
  `pnpm-workspace.yaml` plus a `catalog:` reference in `apps/frontend/package.json` — never a literal
  version, never via `pnpm add` — and `apps/frontend/frontend.nix`'s `hash` must be refreshed through
  `pkgs.lib.fakeHash`.

**Not affected**

- `frontend.nix`'s `extraSrcs` already takes `./src` and `./test` as whole directories, so new files
  there need no Nix change.
- No workspace package, no `tsconfig` graph change, no new app. `apps/frontend` stays a bundler-built
  leaf outside `tsconfig.apps.json`'s `references`.

**Carried-forward assumptions from discovery**

The list is for one person on one device, with no sign-in and nothing shared. A few hundred tasks is
the ceiling, so there is no search or paging. If the saved list cannot be read back, the page opens
empty rather than showing an error — the person loses the old list without being told why. See
`discovery.md` § Assumptions for the full list; each is open to challenge here.
