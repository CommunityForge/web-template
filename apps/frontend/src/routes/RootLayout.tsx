import * as ReactRouter from "react-router"

import * as AppSidebar from "@/components/app-sidebar"
import * as Sidebar from "@/components/ui/sidebar"
import * as Theme from "@/features/theme"

// A pathless layout route (`docs/start/declarative/routing.md` §Layout Routes): it wraps every
// route without contributing a URL segment. It owns the app's ONLY `SidebarProvider`, so sidebar
// state is scoped to the layout rather than the app root. The provider renders the one wrapper div,
// and `flex-1` sizes it as the direct flex child of `#root`, the `flex min-h-svh flex-col` shell in
// `index.html`.
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
