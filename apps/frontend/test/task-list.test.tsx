import { describe, expect, it } from "@effect/vitest"
import { fireEvent, render, waitFor, within } from "@testing-library/react"
import { useCallback, useState } from "react"

import type { Task } from "../src/features/task-list/task.ts"

import { AddTaskForm } from "../src/features/task-list/components/AddTaskForm.tsx"
import { TaskList } from "../src/features/task-list/components/TaskList.tsx"

// Every component here is presentational -- `tasks`/`setTasks` are props all the way down
// from `routes/Tasks.tsx` -- so these tests hold their own `useState` rather than mounting a
// `RegistryProvider` against the real, `localStorage`-backed atom. That keeps them free of the
// durability file's concurrency concerns entirely (see `task-list-storage.test.tsx`).
function AddTaskFormHarness() {
  const [tasks, setTasksState] = useState<ReadonlyArray<Task>>([])
  const setTasks = useCallback((update: (tasks: ReadonlyArray<Task>) => ReadonlyArray<Task>) => {
    setTasksState((previous) => update(previous))
  }, [])

  return (
    <div>
      <AddTaskForm setTasks={setTasks} />
      <ul>
        {tasks.map((task) => (
          <li key={task.id}>{task.text}</li>
        ))}
      </ul>
    </div>
  )
}

function TaskListHarness({ initial }: { readonly initial: ReadonlyArray<Task> }) {
  const [tasks, setTasksState] = useState<ReadonlyArray<Task>>(initial)
  const setTasks = useCallback((update: (tasks: ReadonlyArray<Task>) => ReadonlyArray<Task>) => {
    setTasksState((previous) => update(previous))
  }, [])

  return (
    <TaskList
      tasks={tasks}
      setTasks={setTasks}
    />
  )
}

const TASK_A: Task = { id: "a", text: "Buy milk", done: false }
const TASK_B: Task = { id: "b", text: "Call the dentist", done: false }
const TASK_C: Task = { id: "c", text: "Water the plants", done: false }

// `react-perf/jsx-no-new-array-as-prop` is an error repo-wide, so every array handed to
// `initial` is a module-scope constant rather than an inline literal.
const NO_TASKS: ReadonlyArray<Task> = []
const ONE_TASK: ReadonlyArray<Task> = [TASK_A]
const TWO_TASKS: ReadonlyArray<Task> = [TASK_A, TASK_B]
const THREE_TASKS: ReadonlyArray<Task> = [TASK_A, TASK_B, TASK_C]

describe("AddTaskForm", () => {
  it("adds a task on Enter and clears the box", () => {
    const { container } = render(<AddTaskFormHarness />)
    const input = within(container).getByRole<HTMLInputElement>("textbox", { name: "Add a task" })

    fireEvent.change(input, { target: { value: "Buy milk" } })
    fireEvent.submit(input.closest("form")!)

    expect(within(container).getByText("Buy milk")).toBeDefined()
    expect(input.value).toBe("")
  })

  it("adds nothing and shows no error for an empty or whitespace-only entry", () => {
    const { container } = render(<AddTaskFormHarness />)
    const input = within(container).getByRole("textbox", { name: "Add a task" })

    fireEvent.submit(input.closest("form")!)
    fireEvent.change(input, { target: { value: "   " } })
    fireEvent.submit(input.closest("form")!)

    expect(container.querySelectorAll("li").length).toBe(0)
    expect(within(container).queryByRole("alert")).toBeNull()
  })
})

describe("TaskRow", () => {
  it("ticks a task and leaves it in place", () => {
    const { container } = render(<TaskListHarness initial={TWO_TASKS} />)

    const checkbox = within(container).getByRole("checkbox", { name: `Mark "${TASK_A.text}" as done` })
    fireEvent.click(checkbox)

    const [first] = within(container).getAllByRole("listitem")
    expect(within(first).getByText(TASK_A.text)).toBeDefined()
    expect(checkbox.getAttribute("aria-checked")).toBe("true")
  })

  it("deletes a task immediately, with no way to restore it", () => {
    const { container } = render(<TaskListHarness initial={TWO_TASKS} />)

    fireEvent.click(within(container).getByRole("button", { name: `Delete "${TASK_A.text}"` }))

    expect(within(container).queryByText(TASK_A.text)).toBeNull()
    expect(within(container).getByText(TASK_B.text)).toBeDefined()
    expect(within(container).queryByRole("button", { name: /restore|undo/i })).toBeNull()
  })

  it("keeps a rename on Enter", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    fireEvent.click(within(container).getByRole("button", { name: TASK_A.text }))
    const input = within(container).getByRole("textbox", { name: `Rename "${TASK_A.text}"` })
    fireEvent.change(input, { target: { value: "Buy oat milk" } })
    fireEvent.submit(input.closest("form")!)

    expect(within(container).getByText("Buy oat milk")).toBeDefined()
  })

  it("keeps a rename on blur", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    fireEvent.click(within(container).getByRole("button", { name: TASK_A.text }))
    const input = within(container).getByRole("textbox", { name: `Rename "${TASK_A.text}"` })
    fireEvent.change(input, { target: { value: "Buy oat milk" } })
    fireEvent.blur(input)

    expect(within(container).getByText("Buy oat milk")).toBeDefined()
  })

  it("abandons a rename on Escape", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    fireEvent.click(within(container).getByRole("button", { name: TASK_A.text }))
    const input = within(container).getByRole("textbox", { name: `Rename "${TASK_A.text}"` })
    fireEvent.change(input, { target: { value: "Buy oat milk" } })
    fireEvent.keyDown(input, { key: "Escape" })

    expect(within(container).getByText(TASK_A.text)).toBeDefined()
    expect(within(container).queryByText("Buy oat milk")).toBeNull()
  })

  it("keeps the previous wording when confirming an emptied box", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    fireEvent.click(within(container).getByRole("button", { name: TASK_A.text }))
    const input = within(container).getByRole("textbox", { name: `Rename "${TASK_A.text}"` })
    fireEvent.change(input, { target: { value: "   " } })
    fireEvent.submit(input.closest("form")!)

    expect(within(container).getByText(TASK_A.text)).toBeDefined()
  })
})

describe("TaskList", () => {
  it("shows an inviting empty state on first visit", () => {
    const { container } = render(<TaskListHarness initial={NO_TASKS} />)

    expect(within(container).getByRole("textbox", { name: "Add a task" })).toBeDefined()
    expect(within(container).getByText(/add your first task/i)).toBeDefined()
  })

  it("returns to the empty state after deleting the only remaining task", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    fireEvent.click(within(container).getByRole("button", { name: `Delete "${TASK_A.text}"` }))

    expect(within(container).getByText(/add your first task/i)).toBeDefined()
  })

  it("moves a task up with the keyboard and announces where it landed", async () => {
    const { container } = render(<TaskListHarness initial={THREE_TASKS} />)

    fireEvent.click(within(container).getByRole("button", { name: `Move "${TASK_C.text}" up` }))

    const [, second] = within(container).getAllByRole("listitem")
    expect(within(second).getByText(TASK_C.text)).toBeDefined()

    await waitFor(() => {
      expect(within(container).getByText(`Moved "${TASK_C.text}" to position 2 of 3`)).toBeDefined()
    })
  })

  it("disables move-up on the first task and move-down on the last", () => {
    const { container } = render(<TaskListHarness initial={TWO_TASKS} />)

    expect(within(container).getByRole("button", { name: `Move "${TASK_A.text}" up` })).toHaveProperty("disabled", true)
    expect(within(container).getByRole("button", { name: `Move "${TASK_B.text}" down` })).toHaveProperty(
      "disabled",
      true,
    )
  })

  it("reorders by dragging the third task to the top", () => {
    const { container } = render(<TaskListHarness initial={THREE_TASKS} />)

    const [firstBefore, , thirdBefore] = within(container).getAllByRole("listitem")
    fireEvent.dragStart(thirdBefore)
    fireEvent.dragOver(firstBefore)
    fireEvent.drop(firstBefore)

    const [first, second, third] = within(container).getAllByRole("listitem")
    expect(within(first).getByText(TASK_C.text)).toBeDefined()
    expect(within(second).getByText(TASK_A.text)).toBeDefined()
    expect(within(third).getByText(TASK_B.text)).toBeDefined()
  })

  it("keeps ticking a task from moving it", () => {
    const { container } = render(<TaskListHarness initial={THREE_TASKS} />)

    fireEvent.click(within(container).getByRole("checkbox", { name: `Mark "${TASK_B.text}" as done` }))

    const [, second] = within(container).getAllByRole("listitem")
    expect(within(second).getByText(TASK_B.text)).toBeDefined()
  })

  it("makes the add box and every task's tick, wording, delete and move actions reachable by keyboard", () => {
    const { container } = render(<TaskListHarness initial={ONE_TASK} />)

    expect(within(container).getByRole("textbox", { name: "Add a task" }).getAttribute("tabindex")).not.toBe("-1")
    expect(within(container).getByRole("checkbox", { name: `Mark "${TASK_A.text}" as done` })).toBeDefined()
    expect(within(container).getByRole("button", { name: TASK_A.text })).toBeDefined()
    expect(within(container).getByRole("button", { name: `Delete "${TASK_A.text}"` })).toBeDefined()
    expect(within(container).getByRole("button", { name: `Move "${TASK_A.text}" up` })).toBeDefined()
    expect(within(container).getByRole("button", { name: `Move "${TASK_A.text}" down` })).toBeDefined()
  })

  it("offers nothing to sign in to, share, or belonging to anyone else", () => {
    const { container } = render(<TaskListHarness initial={TWO_TASKS} />)

    expect(within(container).queryByRole("button", { name: /sign in|log in|share/i })).toBeNull()
    expect(within(container).queryByText(/sign in|log in|share/i)).toBeNull()
  })
})
