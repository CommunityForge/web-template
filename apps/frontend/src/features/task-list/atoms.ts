import * as Atom from "effect/unstable/reactivity/Atom"

import * as BrowserStorage from "@/lib/browser-storage"

import * as Task from "./task.ts"

/**
 * The list's own runtime, providing the shared `localStorage`-backed `KeyValueStore`. Module scope -- built on first
 * subscription, disposed with the registry. The layer itself is defined once in `@/lib/browser-storage` so every
 * feature runtime in a registry shares one store rather than building its own.
 */
const runtime = Atom.runtime(BrowserStorage.layerLocalStorage)

/**
 * The task list, durable across a reload on this device (D1 in `design.md`). Left in the default sync mode, so
 * components read `Array<Task>` directly rather than unwrapping an `AsyncResult`. A saved value that no longer decodes
 * falls back to the empty list by construction (D2) -- no bespoke handling needed here.
 */
export const tasksAtom = Atom.kvs({
  runtime,
  key: "task-list:tasks",
  schema: Task.Tasks,
  defaultValue: () => [],
}).pipe(Atom.withLabel("task-list:tasks"))
