import { describe, expect, it } from "@effect/vitest"
import { fireEvent, render, waitFor, within } from "@testing-library/react"
import * as ReactRouter from "react-router"

import * as App from "../src/App.tsx"

// Every query is scoped to its own `container` via `within`. Two things make that mandatory rather
// than stylistic: the shared config sets `sequence.concurrent`, so tests in a file run at the same
// time, and it does not set `globals`, so `@testing-library/react` never registers its automatic
// `afterEach(cleanup)`. Both renders therefore coexist in `document.body`, and an unscoped
// `screen.getByRole` matches across all of them.
//
// `App` is the `<Routes>` tree, so it needs router context to render at all. `<ReactRouter.MemoryRouter>` is
// the declarative-mode equivalent of a test harness -- `createRoutesStub` is data/framework mode
// only (`docs/start/modes.md`). Its default `initialEntries` is `["/"]`, which is the index route.
//
// `initialEntries` values are module-scope constants because `react-perf/jsx-no-new-array-as-prop`
// is an error repo-wide, and the `**/test/**` override only relaxes `no-console`.
const UNKNOWN_PATH = ["/does-not-exist"]

describe("App", () => {
  it("renders the welcome heading", () => {
    const { container } = render(
      <ReactRouter.MemoryRouter>
        <App.App />
      </ReactRouter.MemoryRouter>,
    )

    expect(within(container).getByRole("heading", { name: "Welcome" })).toBeDefined()
  })
})

describe("routing", () => {
  it("renders the not-found route for an unmatched path", () => {
    const { container } = render(
      <ReactRouter.MemoryRouter initialEntries={UNKNOWN_PATH}>
        <App.App />
      </ReactRouter.MemoryRouter>,
    )

    expect(within(container).getByRole("heading", { name: "Page not found" })).toBeDefined()
    expect(within(container).queryByRole("heading", { name: "Welcome" })).toBeNull()
  })

  it("navigates from the not-found route back to the index route", async () => {
    const { container } = render(
      <ReactRouter.MemoryRouter initialEntries={UNKNOWN_PATH}>
        <App.App />
      </ReactRouter.MemoryRouter>,
    )

    fireEvent.click(within(container).getByRole("link", { name: "Back to the home page" }))

    // Client-side navigation re-renders rather than reloading, so the assertion has to wait for
    // React to commit the new match.
    await waitFor(() => {
      expect(within(container).getByRole("heading", { name: "Welcome" })).toBeDefined()
    })
  })
})
