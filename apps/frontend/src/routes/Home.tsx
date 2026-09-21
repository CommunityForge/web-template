import * as ReactRouter from "react-router"

import * as Button from "@/components/ui/button"

// The index route. Every section here is a direct child of the `#root` flex column declared in
// `index.html`, so this returns a fragment rather than a wrapper element.
export function Home() {
  return (
    <section className="flex grow flex-col place-content-center place-items-center px-5 py-8">
      <h1 className="my-6 font-heading text-[56px] font-medium tracking-[-1.68px] text-foreground max-lg:my-4 max-lg:text-[36px]">
        Welcome
      </h1>
      <p className="mb-8 max-w-[36ch]">Manage your tasks from the sidebar, or jump straight in below.</p>
      <ReactRouter.Link
        to="/tasks"
        className={Button.buttonVariants({ variant: "default" })}
      >
        Go to tasks
      </ReactRouter.Link>
    </section>
  )
}
