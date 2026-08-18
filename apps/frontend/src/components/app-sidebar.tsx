import * as Array from "effect/Array"
import { pipe } from "effect/Function"
import * as Predicate from "effect/Predicate"
import { HomeIcon, ListTodoIcon } from "lucide-react"
import { Link, useMatch, useResolvedPath } from "react-router"

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"

interface NavItemProps {
  to: string
  label: string
  end: boolean
  icon?: React.JSX.Element | undefined
  link: React.JSX.Element
}

const NAV_ITEMS: Array.NonEmptyReadonlyArray<NavItemProps> = pipe(
  [
    { to: "/", label: "Home", end: true, icon: <HomeIcon /> },
    { to: "/tasks", label: "Tasks", end: false, icon: <ListTodoIcon /> },
  ] as const,
  Array.map((item) => ({ ...item, link: <Link to={item.to} /> })),
)

function NavItem(props: NavItemProps) {
  const resolved = useResolvedPath(props.to)
  const match = useMatch({ path: resolved.pathname, end: props.end })

  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        isActive={Predicate.isNotNull(match)}
        render={props.link}
      >
        {props.icon ?? null}
        {props.label}
      </SidebarMenuButton>
    </SidebarMenuItem>
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
    <Sidebar
      variant="sidebar"
      collapsible="icon"
    >
      <SidebarHeader />
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>{navItems}</SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter />
    </Sidebar>
  )
}
