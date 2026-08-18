import * as Schema from "effect/Schema"

/**
 * What the user asked for. `"system"` is a preference, not an appearance -- resolving it against the OS is
 * `appearanceAtom`'s job in `atoms.ts`.
 *
 * A schema rather than a bare union because this value round-trips through `localStorage`: `Atom.kvs` decodes with it,
 * so a hand-edited or stale saved value is rejected at the boundary and falls back to the default instead of being
 * asserted into the type with `as Theme`.
 */
export const Theme = Schema.Literals(["dark", "light", "system"])
export type Theme = typeof Theme.Type

/**
 * The two appearances a document can actually be in, once `"system"` has been resolved. Derived from `Theme` so adding
 * a preference cannot leave this behind; no schema, because it is never persisted or parsed.
 */
export type Appearance = Exclude<Theme, "system">
