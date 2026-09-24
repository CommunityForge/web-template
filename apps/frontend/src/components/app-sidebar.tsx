import * as Array from "effect/Array"
import { pipe } from "effect/Function"
import * as Predicate from "effect/Predicate"
import * as Lucide from "lucide-react"
import * as React from "react"
import * as ReactRouter from "react-router"

import * as Sidebar from "@/components/ui/sidebar"

interface NavItemProps {
  to: string
  label: string
  end: boolean
  icon?: React.JSX.Element | undefined
  link: React.JSX.Element
}

const NAV_ITEMS: Array.NonEmptyReadonlyArray<NavItemProps> = pipe(
  [
    { to: "/", label: "Home", end: true, icon: <Lucide.HomeIcon /> },
    { to: "/tasks", label: "Tasks", end: false, icon: <Lucide.ListTodoIcon /> },
  ] as const,
  Array.map((item) => ({ ...item, link: <ReactRouter.Link to={item.to} /> })),
)

function NavItem(props: NavItemProps) {
  const resolved = ReactRouter.useResolvedPath(props.to)
  const match = ReactRouter.useMatch({ path: resolved.pathname, end: props.end })

  return (
    <Sidebar.SidebarMenuItem>
      <Sidebar.SidebarMenuButton
        isActive={Predicate.isNotNull(match)}
        render={props.link}
      >
        {props.icon ?? null}
        {props.label}
      </Sidebar.SidebarMenuButton>
    </Sidebar.SidebarMenuItem>
  )
}

export function AppSidebar() {
  const navItems = Array.map(NAV_ITEMS, (item) => (
    <NavItem
      key={item.to}
      to={item.to}
      icon={item.icon}
      label={item.label}
      end={item.end}
      link={item.link}
    />
  ))
  return (
    <Sidebar.Sidebar
      variant="sidebar"
      collapsible="icon"
    >
      <Sidebar.SidebarHeader />
      <Sidebar.SidebarContent>
        <Sidebar.SidebarGroup>
          <Sidebar.SidebarGroupContent>
            <Sidebar.SidebarMenu>{navItems}</Sidebar.SidebarMenu>
          </Sidebar.SidebarGroupContent>
        </Sidebar.SidebarGroup>
      </Sidebar.SidebarContent>
      <Sidebar.SidebarFooter />
    </Sidebar.Sidebar>
  )
}
