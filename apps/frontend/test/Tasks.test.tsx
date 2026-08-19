import { describe, expect, it } from "@effect/vitest"
import { render, within } from "@testing-library/react"
import * as ReactRouter from "react-router"

import * as App from "../src/App.tsx"

// `initialEntries` is a module-scope constant, per `react-perf/jsx-no-new-array-as-prop`.
const TASKS_PATH = ["/tasks"]

describe("Tasks route", () => {
  it("renders the task list page at /tasks", () => {
    const { container } = render(
      <ReactRouter.MemoryRouter initialEntries={TASKS_PATH}>
        <App.App />
      </ReactRouter.MemoryRouter>,
    )

    expect(within(container).getByRole("textbox", { name: "Add a task" })).toBeDefined()
  })
})
