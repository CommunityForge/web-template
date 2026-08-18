import * as React from "react"

import * as Button from "@/components/ui/button"
import * as Checkbox from "@/components/ui/checkbox"
import * as Input from "@/components/ui/input"

import type { SetTasks, Task } from "../task.ts"

import { moveTask, removeTask, renameTask, toggleTask } from "../task.ts"

export function TaskRow({
  task,
  position,
  total,
  setTasks,
  announce,
  onDragOver,
  onRowDragStart,
  onRowDrop,
}: {
  readonly task: Task
  readonly position: number
  readonly total: number
  readonly setTasks: SetTasks
  readonly announce: (message: string) => void
  readonly onDragOver: React.DragEventHandler<HTMLLIElement>
  readonly onRowDragStart: (id: string) => void
  readonly onRowDrop: (id: string) => void
}) {
  // Editing is view-local until it is confirmed, so `useState` is correct
  // (`apps/frontend/AGENTS.md` § Effect and Atom) -- the mutation itself still goes through
  // `setTasks(renameTask(...))`, same as every other change here.
  const [editing, setEditing] = React.useState(false)
  const [draft, setDraft] = React.useState(task.text)
  const draftInputRef = React.useRef<HTMLInputElement>(null)

  // Focused imperatively rather than via the `autoFocus` prop (`jsx-a11y/no-autofocus`) --
  // this only fires when the row's own rename button is activated, not on page load.
  React.useEffect(() => {
    if (editing) draftInputRef.current?.focus()
  }, [editing])

  const startEditing = React.useCallback(() => {
    setDraft(task.text)
    setEditing(true)
  }, [task.text])

  const commit = React.useCallback(() => {
    setTasks(renameTask(task.id, draft))
    setEditing(false)
  }, [setTasks, task.id, draft])

  const cancel = React.useCallback(() => {
    setDraft(task.text)
    setEditing(false)
  }, [task.text])

  const onDraftSubmit = React.useCallback(
    (event: React.SubmitEvent<HTMLFormElement>) => {
      event.preventDefault()
      commit()
    },
    [commit],
  )

  const onDraftChange = React.useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    setDraft(event.target.value)
  }, [])

  const onDraftKeyDown = React.useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (event.key === "Escape") {
        event.preventDefault()
        cancel()
      }
    },
    [cancel],
  )

  const onToggle = React.useCallback(() => {
    setTasks(toggleTask(task.id))
  }, [setTasks, task.id])

  const onDelete = React.useCallback(() => {
    setTasks(removeTask(task.id))
  }, [setTasks, task.id])

  const move = React.useCallback(
    (direction: "up" | "down") => {
      setTasks(moveTask(task.id, direction))
      const newIndex = direction === "up" ? position - 1 : position + 1
      announce(`Moved "${task.text}" to position ${newIndex + 1} of ${total}`)
    },
    [setTasks, announce, task.id, task.text, position, total],
  )

  const onMoveUp = React.useCallback(() => move("up"), [move])
  const onMoveDown = React.useCallback(() => move("down"), [move])

  const onDragStart = React.useCallback(() => onRowDragStart(task.id), [onRowDragStart, task.id])
  const onDrop = React.useCallback(() => onRowDrop(task.id), [onRowDrop, task.id])

  return (
    // The Move up/down buttons below are the primary, keyboard-operable reordering path
    // (design D6); dragging the row is a mouse-only enhancement on top of it, not a
    // replacement, so the row itself does not need its own interactive role.
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-element-interactions
    <li
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      className="flex items-center gap-2 border-b border-border py-2"
    >
      <Checkbox.Checkbox
        checked={task.done}
        onCheckedChange={onToggle}
        aria-label={`Mark "${task.text}" as done`}
      />

      {editing ? (
        <form
          onSubmit={onDraftSubmit}
          className="flex-1"
        >
          <Input.Input
            ref={draftInputRef}
            aria-label={`Rename "${task.text}"`}
            value={draft}
            onChange={onDraftChange}
            onBlur={commit}
            onKeyDown={onDraftKeyDown}
          />
        </form>
      ) : (
        <button
          type="button"
          onClick={startEditing}
          className="flex-1 text-left"
        >
          {task.text}
        </button>
      )}

      <Button.Button
        type="button"
        variant="ghost"
        size="icon-sm"
        aria-label={`Move "${task.text}" up`}
        disabled={position === 0}
        onClick={onMoveUp}
      >
        ↑
      </Button.Button>
      <Button.Button
        type="button"
        variant="ghost"
        size="icon-sm"
        aria-label={`Move "${task.text}" down`}
        disabled={position === total - 1}
        onClick={onMoveDown}
      >
        ↓
      </Button.Button>
      <Button.Button
        type="button"
        variant="destructive"
        size="sm"
        aria-label={`Delete "${task.text}"`}
        onClick={onDelete}
      >
        Delete
      </Button.Button>
    </li>
  )
}
