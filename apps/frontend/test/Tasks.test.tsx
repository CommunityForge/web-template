import { describe, expect, it } from "@effect/vitest"
import { render, within } from "@testing-library/react"
import { MemoryRouter } from "react-router"

import App from "../src/App.tsx"

// This is the only test in the file that renders the real, `localStorage`-backed `tasksAtom`
// (via `App` -> `Tasks`), so there is nothing else in this file for it to race (see
// `task-list-storage.test.tsx` for the file that owns that concern).
if (typeof window.localStorage === "undefined") {
  const store = new Map<string, string>()
  Object.defineProperty(window, "localStorage", {
    configurable: true,
    value: {
      get length() {
        return store.size
      },
      clear: () => store.clear(),
      getItem: (key: string) => store.get(key) ?? null,
      key: (index: number) => Array.from(store.keys())[index] ?? null,
      removeItem: (key: string) => store.delete(key),
      setItem: (key: string, value: string) => store.set(key, value),
    } satisfies Storage,
  })
}

// `initialEntries` is a module-scope constant, per `react-perf/jsx-no-new-array-as-prop`.
const TASKS_PATH = ["/tasks"]

describe("Tasks route", () => {
  it("renders the task list page at /tasks", () => {
    const { container } = render(
      <MemoryRouter initialEntries={TASKS_PATH}>
        <App />
      </MemoryRouter>,
    )

    expect(within(container).getByRole("textbox", { name: "Add a task" })).toBeDefined()
  })
})
