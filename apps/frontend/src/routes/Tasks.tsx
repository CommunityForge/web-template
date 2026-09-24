import * as Hooks from "@effect/atom-react/Hooks"

import * as TaskList from "@/features/task-list"

export function Tasks() {
  const [tasks, setTasks] = Hooks.useAtom(TaskList.tasksAtom)

  return (
    <section className="flex grow flex-col gap-4 px-5 py-8 text-left">
      <TaskList.TaskList
        tasks={tasks}
        setTasks={setTasks}
      />
    </section>
  )
}
