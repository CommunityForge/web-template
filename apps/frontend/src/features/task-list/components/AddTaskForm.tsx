import * as React from "react"

import * as Input from "@/components/ui/input"

import * as Task from "../task.ts"

export function AddTaskForm({ setTasks }: { readonly setTasks: Task.SetTasks }) {
  const [text, setText] = React.useState("")

  const onChange = React.useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    setText(event.target.value)
  }, [])

  const onSubmit = React.useCallback(
    (event: React.SubmitEvent<HTMLFormElement>) => {
      event.preventDefault()
      setTasks(Task.addTask(text))
      setText("")
    },
    [setTasks, text],
  )

  return (
    <form onSubmit={onSubmit}>
      <Input.Input
        aria-label="Add a task"
        placeholder="Add a task"
        value={text}
        onChange={onChange}
      />
    </form>
  )
}
