import * as Hooks from "@effect/atom-react/Hooks"
import * as Lucide from "lucide-react"
import * as React from "react"

import * as Button from "@/components/ui/button"
import * as DropdownMenu from "@/components/ui/dropdown-menu"

import type * as Theme from "../theme.ts"

import * as Atoms from "../atoms.ts"

interface ThemeOptionProps {
  theme: Theme.Theme
  label: string
}

/**
 * One row of the menu, extracted so its click handler can be a stable reference: `onClick={() => setTheme("light")}`
 * builds a new function on every render of the toggle, which `react-perf/jsx-no-new-function-as-prop` rejects. Bound to
 * this row's own props, the handler is built once per row instead.
 */
function ThemeOption(props: ThemeOptionProps) {
  const setTheme = Hooks.useAtomSet(Atoms.themeAtom)
  const select = React.useCallback(() => setTheme(props.theme), [setTheme, props.theme])

  return <DropdownMenu.DropdownMenuItem onClick={select}>{props.label}</DropdownMenu.DropdownMenuItem>
}

// The trigger is constant, so it is built once at module scope -- the hoisting
// `react-perf/jsx-no-jsx-as-prop` asks for, the same treatment the route elements get in `App.tsx`.
// It goes through `render` rather than being nested inside the trigger: the trigger *is* a
// `<button>`, and a `<button>` inside a `<button>` is invalid HTML.
const TRIGGER = (
  <Button.Button
    variant="outline"
    size="icon"
  >
    <Lucide.Sun className="h-[1.2rem] w-[1.2rem] scale-100 rotate-0 transition-all dark:scale-0 dark:-rotate-90" />
    <Lucide.Moon className="absolute h-[1.2rem] w-[1.2rem] scale-0 rotate-90 transition-all dark:scale-100 dark:rotate-0" />
    <span className="sr-only">Toggle theme</span>
  </Button.Button>
)

export function ModeToggle() {
  return (
    <DropdownMenu.DropdownMenu>
      <DropdownMenu.DropdownMenuTrigger render={TRIGGER} />
      <DropdownMenu.DropdownMenuContent align="end">
        <ThemeOption
          theme="light"
          label="Light"
        />
        <ThemeOption
          theme="dark"
          label="Dark"
        />
        <ThemeOption
          theme="system"
          label="System"
        />
      </DropdownMenu.DropdownMenuContent>
    </DropdownMenu.DropdownMenu>
  )
}
