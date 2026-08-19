import * as ReactRouter from "react-router"

import * as Button from "@/components/ui/button"

// Arbitrary font sizes rather than `text-5xl`/`text-lg`: Tailwind's named sizes ship a paired
// line-height and this app's type inherits 145% from `:root`.
const STATUS = "font-mono text-[15px]/[135%] tracking-[0.18em] text-primary uppercase"
const HEADING =
  "my-6 font-heading text-[56px] font-medium tracking-[-1.68px] text-foreground max-lg:my-4 max-lg:text-[36px]"

// Same treatment as the links on the home page: a styled `<a>`, not `<Button render={<a/>}>`.
// `<Link>` renders a real anchor with an `href`, so it keeps link semantics while picking up the
// `secondary` variant's colors.
const LINK = Button.buttonVariants({
  variant: "secondary",
  className:
    "gap-2 rounded-[6px] px-3 py-1.5 text-base font-normal transition-shadow duration-300 hover:bg-secondary hover:shadow-link",
})

// The `path="*"` route. This is a rendered not-found view only -- a client-only SPA has already
// been served a 200 by the time React runs, so it cannot turn this into a real 404 status.
export function NotFound() {
  return (
    <section className="flex grow flex-col place-content-center place-items-center px-5 py-8">
      <p className={STATUS}>404</p>
      <h1 className={HEADING}>Page not found</h1>
      <p className="mb-8 max-w-[36ch]">That URL does not match any route in this app.</p>
      <ReactRouter.Link
        to="/"
        className={LINK}
      >
        Back to the home page
      </ReactRouter.Link>
    </section>
  )
}
