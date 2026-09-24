import * as Hooks from "@effect/atom-react/Hooks"
import * as RegistryContext from "@effect/atom-react/RegistryContext"
import { describe, expect, it } from "@effect/vitest"
import { fireEvent, render, waitFor, within } from "@testing-library/react"
import * as React from "react"

import * as TaskList from "../src/features/task-list"

const STORAGE_KEY = "task-list:tasks"

const Harness = () => {
  const [tasks, setTasks] = Hooks.useAtom(TaskList.tasksAtom)

  const addOne = React.useCallback(
    () => setTasks((previous) => [...previous, { id: "seeded", text: "Seeded task", done: false }]),
    [setTasks],
  )

  return (
    <div>
      <span data-testid="count">{tasks.length}</span>
      <button onClick={addOne}>add</button>
    </div>
  )
}

describe("task-list durability", { concurrent: false }, () => {
  it("is the empty list when nothing is saved", () => {
    const { container } = render(
      <RegistryContext.RegistryProvider>
        <Harness />
      </RegistryContext.RegistryProvider>,
    )

    expect(within(container).getByTestId("count").textContent).toBe("0")
  })

  it("reads back a written list after remounting", async () => {
    const { container, unmount } = render(
      <RegistryContext.RegistryProvider>
        <Harness />
      </RegistryContext.RegistryProvider>,
    )

    fireEvent.click(within(container).getByRole("button", { name: "add" }))

    // Wait for the actual write to land in storage, not just the optimistic in-memory update --
    // the two happen on different atoms and are not guaranteed to land in the same tick.
    await waitFor(() => {
      expect(localStorage.getItem(STORAGE_KEY)).not.toBeNull()
    })
    unmount()

    const { container: remounted } = render(
      <RegistryContext.RegistryProvider>
        <Harness />
      </RegistryContext.RegistryProvider>,
    )

    await waitFor(() => {
      expect(within(remounted).getByTestId("count").textContent).toBe("1")
    })
  })

  it("falls back to the empty list when the saved value cannot be read back, and stays writable", async () => {
    localStorage.setItem(STORAGE_KEY, "not valid json")

    const { container } = render(
      <RegistryContext.RegistryProvider>
        <Harness />
      </RegistryContext.RegistryProvider>,
    )

    expect(within(container).getByTestId("count").textContent).toBe("0")

    fireEvent.click(within(container).getByRole("button", { name: "add" }))

    await waitFor(() => {
      expect(within(container).getByTestId("count").textContent).toBe("1")
    })
  })
})
