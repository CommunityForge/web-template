/**
 * Deny-by-default for the Supabase Data API.
 *
 * ## The invariant, and why RLS alone does not hold it
 *
 * PostgREST connects as `anon` or `authenticated`. Two independent things decide what those roles can do:
 *
 * - a `GRANT` decides whether the role can reach a table _at all_: with none, the request is rejected before RLS is ever
 *   consulted;
 * - `ENABLE ROW LEVEL SECURITY` plus a policy decides which rows it sees once it is in.
 *
 * So the invariant is not "every table has RLS". It is **"every table in an exposed schema is either ungranted, or
 * granted AND RLS-enabled AND has a policy"**. Supabase's stock default privileges grant every new table in `public` to
 * both roles, which is the half a per-table policy silently relies on.
 *
 * ## Why this is a blanket rule rather than per-table discipline
 *
 * `supabase/config.toml` exposes `public`, and tables land in that schema from more than one author: this package's
 * migrations, the migrator's own `effect_sql_migrations` ledger, and any runtime that creates its tables on start. A
 * per-table policy cannot cover a table no migration of ours creates.
 *
 * `ALTER DEFAULT PRIVILEGES` covers tables that do not exist yet, whoever creates them. That makes exposure an explicit
 * opt-in per table from here on: a table is reachable through the Data API only when a later migration grants it, in
 * the same statement as the policy that says which rows.
 *
 * ## The one thing to keep an eye on
 *
 * `ALTER DEFAULT PRIVILEGES` applies only to objects created by the role it names. Everything connects as `DB_USER`
 * today, so one `FOR ROLE` clause covers it all. If that ever diverges (a dedicated migration role, say) this rule must
 * be repeated for each role, or new tables will silently start arriving granted again. `bin/audit.ts` is the check that
 * would catch it.
 *
 * @since 0.0.0
 */

import * as Effect from "effect/Effect"
import * as SqlClient from "effect/unstable/sql/SqlClient"

/**
 * @since 0.0.0
 * @category migrations
 */
export const migration = Effect.gen(function* () {
  const sql = yield* SqlClient.SqlClient

  // The role everything connects as; also the role whose future objects the default privileges below govern.
  const owner = sql.literal("postgres")

  // Existing tables.
  yield* sql`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated`

  yield* sql`REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated`

  // Everything created from here on, by the owner role, regardless of which codebase creates it.
  yield* sql`ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated`

  yield* sql`ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated`
})
