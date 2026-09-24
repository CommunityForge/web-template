import * as ReactRouter from "react-router"

import * as Home from "./routes/Home.tsx"
import * as NotFound from "./routes/NotFound.tsx"
import * as RootLayout from "./routes/RootLayout.tsx"
import * as Tasks from "./routes/Tasks.tsx"

// The route elements are hoisted out of the tree below because `react-perf/jsx-no-jsx-as-prop` is
// an error repo-wide and `<Route element={<Home />} />` is JSX-as-prop by construction. Hoisting is
// what the rule asks for rather than a workaround: these elements are constant, so building them
// once at module scope is strictly less work than rebuilding them on every render of `App`.
const LAYOUT = <RootLayout.RootLayout />
const HOME = <Home.Home />
const TASKS = <Tasks.Tasks />
const NOT_FOUND = <NotFound.NotFound />

// Declarative mode (`docs/start/modes.md`): the route table *is* React, so `App` is the table and
// there is no `routes.tsx` indirection. The `<BrowserRouter>` that supplies its context lives in
// `main.tsx`, which keeps `App` renderable under a `<MemoryRouter>` in tests.
//
// Adding a route: drop a component in `src/routes/`, add a `const` for its element above, and add
// one `<Route>` line inside the layout route -- above the `path="*"` catch-all, which matches
// anything and so must stay last.
//
// Exported by name rather than as a default: a default import cannot be namespace-qualified, and
// the repo-wide import style (root `AGENTS.md` § Import style) is that every import binds a
// namespace.
export function App() {
  return (
    <ReactRouter.Routes>
      <ReactRouter.Route element={LAYOUT}>
        <ReactRouter.Route
          index
          element={HOME}
        />
        <ReactRouter.Route
          path="tasks"
          element={TASKS}
        />
        <ReactRouter.Route
          path="*"
          element={NOT_FOUND}
        />
      </ReactRouter.Route>
    </ReactRouter.Routes>
  )
}
