import { describe, expect, it } from "@effect/vitest"

import * as Task from "../src/features/task-list/task.ts"

describe("makeTask", () => {
  it("carries its wording and is not done", () => {
    const task = Task.makeTask("Buy milk")

    expect(task.text).toBe("Buy milk")
    expect(task.done).toBe(false)
  })

  it("gives two tasks different ids", () => {
    const first = Task.makeTask("Buy milk")
    const second = Task.makeTask("Call the dentist")

    expect(first.id).not.toBe(second.id)
  })
})

describe("addTask", () => {
  it("adds a task", () => {
    const tasks = Task.addTask("Buy milk")([])

    expect(tasks.map((task) => task.text)).toEqual(["Buy milk"])
  })

  it("adds a second task below the first", () => {
    const tasks = Task.addTask("Call the dentist")(Task.addTask("Buy milk")([]))

    expect(tasks.map((task) => task.text)).toEqual(["Buy milk", "Call the dentist"])
  })

  it("adds nothing for an empty or whitespace-only entry", () => {
    const tasks = Task.addTask("Buy milk")([])

    expect(Task.addTask("")(tasks)).toBe(tasks)
    expect(Task.addTask("   ")(tasks)).toBe(tasks)
  })
})

// The blocks below build their fixture from `makeTask` rather than `addTask` so the task under
// test is a named binding -- there is nothing to dig back out of the list by index, and the
// fixture does not depend on `addTask` (covered above) behaving correctly.
describe("toggleTask", () => {
  it("ticks a task", () => {
    const first = Task.makeTask("Buy milk")
    const tasks: ReadonlyArray<Task.Task> = [first]

    const toggled = Task.toggleTask(first.id)(tasks)

    expect(toggled.map((task) => task.done)).toEqual([true])
  })

  it("unticks a ticked task", () => {
    const first = Task.makeTask("Buy milk")
    const tasks: ReadonlyArray<Task.Task> = [first]

    const ticked = Task.toggleTask(first.id)(tasks)
    const unticked = Task.toggleTask(first.id)(ticked)

    expect(unticked.map((task) => task.done)).toEqual([false])
  })

  it("leaves a ticked task in the same position", () => {
    const first = Task.makeTask("Buy milk")
    const second = Task.makeTask("Call the dentist")
    const tasks: ReadonlyArray<Task.Task> = [first, second]

    const toggled = Task.toggleTask(first.id)(tasks)

    expect(toggled.map((task) => task.text)).toEqual(["Buy milk", "Call the dentist"])
  })
})

describe("renameTask", () => {
  it("replaces wording for one id", () => {
    const first = Task.makeTask("Buy milk")
    const tasks: ReadonlyArray<Task.Task> = [first]

    const renamed = Task.renameTask(first.id, "Buy oat milk")(tasks)

    expect(renamed.map((task) => task.text)).toEqual(["Buy oat milk"])
  })

  it("keeps done and position when renaming", () => {
    const first = Task.makeTask("Buy milk")
    const second = Task.makeTask("Call the dentist")
    const tasks: ReadonlyArray<Task.Task> = [first, second]

    const ticked = Task.toggleTask(first.id)(tasks)
    const renamed = Task.renameTask(first.id, "Buy oat milk")(ticked)

    expect(renamed.map((task) => task.text)).toEqual(["Buy oat milk", "Call the dentist"])
    expect(renamed.map((task) => task.done)).toEqual([true, false])
  })

  it("returns the list unchanged for an empty or whitespace-only wording", () => {
    const first = Task.makeTask("Buy milk")
    const tasks: ReadonlyArray<Task.Task> = [first]

    expect(Task.renameTask(first.id, "")(tasks)).toBe(tasks)
    expect(Task.renameTask(first.id, "   ")(tasks)).toBe(tasks)
  })
})

describe("removeTask", () => {
  it("drops one id, the rest keeping their relative order", () => {
    const first = Task.makeTask("First")
    const second = Task.makeTask("Second")
    const third = Task.makeTask("Third")
    const tasks: ReadonlyArray<Task.Task> = [first, second, third]

    const removed = Task.removeTask(second.id)(tasks)

    expect(removed.map((task) => task.text)).toEqual(["First", "Third"])
  })
})

describe("moveTask", () => {
  it("moves a task to the top", () => {
    const first = Task.makeTask("First")
    const second = Task.makeTask("Second")
    const third = Task.makeTask("Third")
    const tasks: ReadonlyArray<Task.Task> = [first, second, third]

    const moved = Task.moveTask(third.id, "up")(Task.moveTask(third.id, "up")(tasks))

    expect(moved.map((task) => task.text)).toEqual(["Third", "First", "Second"])
  })

  it("moves a task down", () => {
    const first = Task.makeTask("First")
    const second = Task.makeTask("Second")
    const third = Task.makeTask("Third")
    const tasks: ReadonlyArray<Task.Task> = [first, second, third]

    const moved = Task.moveTask(first.id, "down")(tasks)

    expect(moved.map((task) => task.text)).toEqual(["Second", "First", "Third"])
  })

  it("is a no-op moving the first task up", () => {
    const first = Task.makeTask("First")
    const second = Task.makeTask("Second")
    const tasks: ReadonlyArray<Task.Task> = [first, second]

    expect(Task.moveTask(first.id, "up")(tasks)).toBe(tasks)
  })

  it("is a no-op moving the last task down", () => {
    const first = Task.makeTask("First")
    const second = Task.makeTask("Second")
    const tasks: ReadonlyArray<Task.Task> = [first, second]

    expect(Task.moveTask(second.id, "down")(tasks)).toBe(tasks)
  })
})
