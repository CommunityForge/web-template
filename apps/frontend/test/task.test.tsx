import { describe, expect, it } from "@effect/vitest"

import { addTask, makeTask, moveTask, removeTask, renameTask, toggleTask } from "../src/features/task-list/task.ts"

describe("makeTask", () => {
  it("carries its wording and is not done", () => {
    const task = makeTask("Buy milk")

    expect(task.text).toBe("Buy milk")
    expect(task.done).toBe(false)
  })

  it("gives two tasks different ids", () => {
    const first = makeTask("Buy milk")
    const second = makeTask("Call the dentist")

    expect(first.id).not.toBe(second.id)
  })
})

describe("addTask", () => {
  it("adds a task", () => {
    const tasks = addTask("Buy milk")([])

    expect(tasks.map((task) => task.text)).toEqual(["Buy milk"])
  })

  it("adds a second task below the first", () => {
    const tasks = addTask("Call the dentist")(addTask("Buy milk")([]))

    expect(tasks.map((task) => task.text)).toEqual(["Buy milk", "Call the dentist"])
  })

  it("adds nothing for an empty or whitespace-only entry", () => {
    const tasks = addTask("Buy milk")([])

    expect(addTask("")(tasks)).toBe(tasks)
    expect(addTask("   ")(tasks)).toBe(tasks)
  })
})

describe("toggleTask", () => {
  it("ticks a task", () => {
    const tasks = addTask("Buy milk")([])
    const toggled = toggleTask(tasks[0].id)(tasks)

    expect(toggled[0].done).toBe(true)
  })

  it("unticks a ticked task", () => {
    const tasks = addTask("Buy milk")([])
    const ticked = toggleTask(tasks[0].id)(tasks)
    const unticked = toggleTask(tasks[0].id)(ticked)

    expect(unticked[0].done).toBe(false)
  })

  it("leaves a ticked task in the same position", () => {
    const tasks = addTask("Call the dentist")(addTask("Buy milk")([]))
    const toggled = toggleTask(tasks[0].id)(tasks)

    expect(toggled.map((task) => task.text)).toEqual(["Buy milk", "Call the dentist"])
  })
})

describe("renameTask", () => {
  it("replaces wording for one id", () => {
    const tasks = addTask("Buy milk")([])
    const renamed = renameTask(tasks[0].id, "Buy oat milk")(tasks)

    expect(renamed[0].text).toBe("Buy oat milk")
  })

  it("keeps done and position when renaming", () => {
    const tasks = addTask("Call the dentist")(addTask("Buy milk")([]))
    const ticked = toggleTask(tasks[0].id)(tasks)
    const renamed = renameTask(tasks[0].id, "Buy oat milk")(ticked)

    expect(renamed.map((task) => task.text)).toEqual(["Buy oat milk", "Call the dentist"])
    expect(renamed[0].done).toBe(true)
  })

  it("returns the list unchanged for an empty or whitespace-only wording", () => {
    const tasks = addTask("Buy milk")([])

    expect(renameTask(tasks[0].id, "")(tasks)).toBe(tasks)
    expect(renameTask(tasks[0].id, "   ")(tasks)).toBe(tasks)
  })
})

describe("removeTask", () => {
  it("drops one id, the rest keeping their relative order", () => {
    const tasks = addTask("Third")(addTask("Second")(addTask("First")([])))
    const removed = removeTask(tasks[1].id)(tasks)

    expect(removed.map((task) => task.text)).toEqual(["First", "Third"])
  })
})

describe("moveTask", () => {
  it("moves a task to the top", () => {
    const tasks = addTask("Third")(addTask("Second")(addTask("First")([])))
    const moved = moveTask(tasks[2].id, "up")(moveTask(tasks[2].id, "up")(tasks))

    expect(moved.map((task) => task.text)).toEqual(["Third", "First", "Second"])
  })

  it("moves a task down", () => {
    const tasks = addTask("Third")(addTask("Second")(addTask("First")([])))
    const moved = moveTask(tasks[0].id, "down")(tasks)

    expect(moved.map((task) => task.text)).toEqual(["Second", "First", "Third"])
  })

  it("is a no-op moving the first task up", () => {
    const tasks = addTask("Second")(addTask("First")([]))

    expect(moveTask(tasks[0].id, "up")(tasks)).toBe(tasks)
  })

  it("is a no-op moving the last task down", () => {
    const tasks = addTask("Second")(addTask("First")([]))

    expect(moveTask(tasks[1].id, "down")(tasks)).toBe(tasks)
  })
})
