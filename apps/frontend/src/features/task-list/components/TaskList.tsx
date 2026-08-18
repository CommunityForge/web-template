import * as React from "react"

import * as Tasks from "../task.ts"
import { AddTaskForm } from "./AddTaskForm.tsx"
import { TaskRow } from "./TaskRow.tsx"

export function TaskList({
  tasks,
  setTasks,
}: {
  readonly tasks: ReadonlyArray<Tasks.Task>
  readonly setTasks: Tasks.SetTasks
}) {
  // Both are view-local UI state, not list data: the announcement is a transient message and
  // the dragged id only matters mid-gesture, so neither belongs in the durable atom.
  const [announcement, setAnnouncement] = React.useState("")
  const draggedId = React.useRef<string | null>(null)

  const onDragOver: React.DragEventHandler<HTMLLIElement> = React.useCallback((event) => {
    event.preventDefault()
  }, [])

  const onRowDragStart = React.useCallback((id: string) => {
    draggedId.current = id
  }, [])

  // Reorders through repeated single-step `moveTask` calls -- the same transform 3.5's
  // up/down buttons use -- rather than a bespoke splice-to-index transform.
  const onRowDrop = React.useCallback(
    (targetId: string) => {
      const sourceId = draggedId.current
      draggedId.current = null
      if (sourceId === null || sourceId === targetId) return

      setTasks((current) => {
        const sourceIndex = current.findIndex((task) => task.id === sourceId)
        const targetIndex = current.findIndex((task) => task.id === targetId)
        if (sourceIndex === -1 || targetIndex === -1) return current

        let next = current
        if (sourceIndex > targetIndex) {
          for (let i = sourceIndex; i > targetIndex; i--) {
            next = Tasks.moveTask(sourceId, "up")(next)
          }
        } else {
          for (let i = sourceIndex; i < targetIndex; i++) {
            next = Tasks.moveTask(sourceId, "down")(next)
          }
        }
        return next
      })
    },
    [setTasks],
  )

  return (
    <div>
      <AddTaskForm setTasks={setTasks} />

      <div
        aria-live="polite"
        className="sr-only"
      >
        {announcement}
      </div>

      {tasks.length === 0 ? (
        <p>Add your first task to get started.</p>
      ) : (
        <ul>
          {tasks.map((task, index) => (
            <TaskRow
              key={task.id}
              task={task}
              position={index}
              total={tasks.length}
              setTasks={setTasks}
              announce={setAnnouncement}
              onDragOver={onDragOver}
              onRowDragStart={onRowDragStart}
              onRowDrop={onRowDrop}
            />
          ))}
        </ul>
      )}
    </div>
  )
}
