import * as Atom from "effect/unstable/reactivity/Atom"

import { layerLocalStorage } from "@/lib/browser-storage"

import { type Appearance, Theme } from "./theme.ts"

/**
 * This feature's runtime, providing the `KeyValueStore` that `Atom.kvs` writes the preference to.
 */
const runtime = Atom.runtime(layerLocalStorage)

/**
 * The user's preference, durable across a reload on this device.
 *
 * The key is the one the previous React-context provider used, so an existing choice is still found; its value was a
 * bare `dark`, whereas the schema store writes JSON, so exactly one saved preference per browser decodes as garbage and
 * falls back to `"dark"`.
 */
export const themeAtom = Atom.kvs({
  runtime,
  key: "vite-ui-theme",
  schema: Theme,
  defaultValue: (): Theme => "dark",
}).pipe(Atom.withLabel("theme:preference"))

/**
 * The OS-level appearance, as a self-cleaning external source: one `matchMedia` listener per registry rather than one
 * per component, torn down with the atom's last subscriber. Reading it live also means a preference of `"system"` now
 * follows the OS while the tab is open, which the one-shot `matchMedia` read it replaces did not.
 */
const systemAppearanceAtom = Atom.make<Appearance>((get) => {
  const query = window.matchMedia("(prefers-color-scheme: dark)")
  const appearance = (): Appearance => (query.matches ? "dark" : "light")
  const update = () => get.setSelf(appearance())

  query.addEventListener("change", update)
  get.addFinalizer(() => query.removeEventListener("change", update))

  return appearance()
}).pipe(Atom.withLabel("theme:system"))

/**
 * The appearance to actually render: the preference, with `"system"` resolved. The dependency on `systemAppearanceAtom`
 * is registered by reading it, so it is subscribed only while the preference is `"system"` -- no listener runs for a
 * user who picked a side.
 */
export const appearanceAtom = Atom.make<Appearance>((get) => {
  const theme = get(themeAtom)
  return theme === "system" ? get(systemAppearanceAtom) : theme
}).pipe(Atom.withLabel("theme:appearance"))
