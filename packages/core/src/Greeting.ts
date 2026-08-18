/**
 * A deliberately trivial module. It exists to prove the scaffolding end-to-end -- project references, source-first
 * exports, the `dist` swap, and the Nix build -- and is meant to be deleted once real modules land.
 *
 * @since 0.0.0
 */

/**
 * The name to greet.
 *
 * @since 0.0.0
 */
export type Subject = string

/**
 * Render a greeting.
 *
 * @since 0.0.0
 */
export const make = (subject: Subject): string => `Hello, ${subject}!`
