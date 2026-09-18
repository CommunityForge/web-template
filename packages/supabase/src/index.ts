/**
 * Effect bindings for Supabase.
 *
 * The package wraps `supabase-js` and nothing else: it owns the _shape_ of a Supabase token and session, while what
 * those claims mean is the consuming domain's business. `internal/*` is not re-exported here and is blocked by the
 * `exports` map.
 *
 * @since 0.0.0
 */

/**
 * @since 0.0.0
 */
export * as SupabaseAuth from "./SupabaseAuth.js"
/**
 * @since 0.0.0
 */
export * as SupabaseClaims from "./SupabaseClaims.js"
/**
 * @since 0.0.0
 */
export * as SupabaseClient from "./SupabaseClient.js"
