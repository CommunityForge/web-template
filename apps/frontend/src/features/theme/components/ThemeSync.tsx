import * as Hooks from "@effect/atom-react/Hooks"
import * as React from "react"

import * as Atoms from "../atoms.ts"

/**
 * Mirrors `appearanceAtom` onto `<html>`'s class list, which is what Tailwind's `dark:` variant reads. Renders nothing
 * -- it is a mount point for the atom, not UI, and so belongs next to the app root rather than inside any screen.
 *
 * `useEffect` is correct here and is one of the few places it is: the decision lives in the atom graph, and this only
 * writes the result out to a DOM node React does not own.
 */
export function ThemeSync() {
  const appearance = Hooks.useAtomValue(Atoms.appearanceAtom)

  React.useEffect(() => {
    const root = window.document.documentElement
    root.classList.remove("light", "dark")
    root.classList.add(appearance)
  }, [appearance])

  return null
}
