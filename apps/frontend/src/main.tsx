import * as RegistryContext from "@effect/atom-react/RegistryContext"
import * as React from "react"
import * as ReactDom from "react-dom/client"
import * as ReactRouter from "react-router"

import * as Sidebar from "@/components/ui/sidebar"
import * as Tooltip from "@/components/ui/tooltip"
import "@/index.css"
import * as Theme from "@/features/theme"

import * as App from "./App.tsx"

// `RegistryProvider` is not strictly required -- `@effect/atom-react` falls back to a registry
// created at module scope, and a single-page app has exactly one client, so that fallback would
// work. It is mounted anyway because it is the seam for `initialValues` (SSR/test seeding) and for
// giving a subtree its own isolated registry; without it there is nowhere to hang either.
//
// It sits *outside* `BrowserRouter` deliberately: the registry is app-scope infrastructure, and
// nesting it inside the router would tie atom lifetimes to navigation.
//
// `ThemeSync` sits *inside* it for the opposite reason: the theme is atom state, so its subscriber
// has to resolve against this registry rather than the module-scope fallback. It renders nothing
// and is the app's only subscriber to the theme unless a `ModeToggle` is on screen, which is why
// it is mounted at the root rather than left to whichever screen happens to show the toggle.
//
// `BrowserRouter` rather than `HashRouter` -- real paths, no `#`. The cost is that a static host
// must rewrite unknown paths to `/index.html`; `vite dev` and `vite preview` already do, but a
// deployment target has to be configured for it. See `README.md`.
ReactDom.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <RegistryContext.RegistryProvider>
      <Theme.ThemeSync />
      <Tooltip.TooltipProvider>
        <Sidebar.SidebarProvider>
          <ReactRouter.BrowserRouter>
            <App.App />
          </ReactRouter.BrowserRouter>
        </Sidebar.SidebarProvider>
      </Tooltip.TooltipProvider>
    </RegistryContext.RegistryProvider>
  </React.StrictMode>,
)
