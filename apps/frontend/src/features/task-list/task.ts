import * as Schema from "effect/Schema"

export const Task = Schema.Struct({
  id: Schema.String,
  text: Schema.String,
  done: Schema.Boolean,
})
export type Task = typeof Task.Type

export const Tasks = Schema.Array(Task)
export type Tasks = typeof Tasks.Type

// Behind one function so that if `crypto.randomUUID` turns out to be unavailable under
// happy-dom, the fallback is a single edit here rather than a sweep of every call site.
const makeId = (): string => crypto.randomUUID()

export const makeTask = (text: string): Task => ({
  id: makeId(),
  text,
  done: false,
})

export type Transform = (tasks: ReadonlyArray<Task>) => ReadonlyArray<Task>

/**
 * The shape every task-list component receives to mutate the list -- never the atom itself.
 */
export type SetTasks = (update: Transform) => void

export const addTask =
  (text: string): Transform =>
  (tasks) => {
    const trimmed = text.trim()
    if (trimmed === "") return tasks
    return [...tasks, makeTask(trimmed)]
  }

export const toggleTask =
  (id: string): Transform =>
  (tasks) =>
    tasks.map((task) => (task.id === id ? { ...task, done: !task.done } : task))

export const renameTask =
  (id: string, text: string): Transform =>
  (tasks) => {
    const trimmed = text.trim()
    if (trimmed === "") return tasks
    return tasks.map((task) => (task.id === id ? { ...task, text: trimmed } : task))
  }

export const removeTask =
  (id: string): Transform =>
  (tasks) =>
    tasks.filter((task) => task.id !== id)

export const moveTask =
  (id: string, direction: "up" | "down"): Transform =>
  (tasks) => {
    const index = tasks.findIndex((task) => task.id === id)
    if (index === -1) return tasks

    const target = direction === "up" ? index - 1 : index + 1
    if (target < 0 || target >= tasks.length) return tasks

    const next = [...tasks]
    const [moved] = next.splice(index, 1)
    next.splice(target, 0, moved)
    return next
  }
