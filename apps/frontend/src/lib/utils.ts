import * as Clsx from "clsx"
import * as TailwindMerge from "tailwind-merge"

export function cn(...inputs: Array<Clsx.ClassValue>) {
  return TailwindMerge.twMerge(Clsx.clsx(inputs))
}
