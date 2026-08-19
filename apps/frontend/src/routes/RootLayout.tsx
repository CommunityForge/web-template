import * as ReactRouter from "react-router"

import * as AppSidebar from "@/components/app-sidebar"
import * as Sidebar from "@/components/ui/sidebar"
import * as Theme from "@/features/theme"

// A pathless layout route (`docs/start/declarative/routing.md` §Layout Routes): it wraps every
// route without contributing a URL segment. It returns a fragment, not a wrapper element -- the
// `#root` div in `index.html` is the `flex min-h-svh flex-col` shell, and each route's top-level
// `<section>` sizes itself as a direct flex child of it. A fragment keeps the nav and the
// matched route's `<section>` both direct children, rather than nesting the route under the nav.
export function RootLayout() {
  return (
    <Sidebar.SidebarProvider className="flex-1">
      <AppSidebar.AppSidebar />
      <Sidebar.SidebarInset>
        <header className="flex h-12 items-center border-b border-border px-3">
          <Sidebar.SidebarTrigger />
          <div className="grow" />
          <Theme.ModeToggle />
        </header>
        <ReactRouter.Outlet />
      </Sidebar.SidebarInset>
    </Sidebar.SidebarProvider>
  )
}
