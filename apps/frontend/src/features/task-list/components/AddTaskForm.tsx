import * as React from "react"

import * as Input from "@/components/ui/input"

import * as Tasks from "../task.ts"

export function AddTaskForm({ setTasks }: { readonly setTasks: Tasks.SetTasks }) {
  const [text, setText] = React.useState("")

  const onChange = React.useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    setText(event.target.value)
  }, [])

  const onSubmit = React.useCallback(
    (event: React.SubmitEvent<HTMLFormElement>) => {
      event.preventDefault()
      setTasks(Tasks.addTask(text))
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
