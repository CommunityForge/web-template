/**
 * Assert that nothing in an API-exposed schema is reachable without row-level security.
 *
 * `0001_data_api_lockdown.ts` establishes deny-by-default, but a migration is a one-time act and the property it
 * establishes is ongoing: a runtime can create tables in the schema long after any migration of ours has run, a future
 * `GRANT` can be written without its matching policy, and `ALTER DEFAULT PRIVILEGES` silently stops applying if the
 * creating role ever changes. None of those show up as a failing build.
 *
 * So this is the standing check rather than a convention to remember. It exits non-zero on any violation, which is what
 * makes it usable from CI and after `db-migrate`. A convention nobody can run is not an invariant.
 *
 * Run with `nix run .#db-audit`, or directly:
 *
 * ```sh
 * pnpm exec tsx ./packages/db/src/bin/audit.ts
 * ```
 *
 * The database is `DB_URL` when set, else the five `DB_*` values. This file is also bundled to `build/audit.js`, one
 * self-contained module importing only `node:*`, which is how it runs where no workspace is installed.
 *
 * @since 0.0.0
 */

import * as NodeRuntime from "@effect/platform-node/NodeRuntime"
import * as Effect from "effect/Effect"
import * as Schema from "effect/Schema"
import * as SqlClient from "effect/unstable/sql/SqlClient"

import { PgAutoLive } from "../Pg.js"

/**
 * Schemas Supabase exposes through PostgREST, per `supabase/config.toml`'s `[api] schemas`. Kept here rather than read
 * from the database because it is a statement of what _should_ be exposed — if the two drift, that is itself the
 * finding.
 */
const EXPOSED_SCHEMAS = ["public"] as const

interface Violation {
  readonly table_schema: string
  readonly table_name: string
  readonly grantee: string
  readonly privileges: string
}

/**
 * The audit's own failure: at least one exposed table is reachable without row security. The violations are already
 * logged in full by the time this fails, so it carries only the count.
 */
class DataApiExposed extends Schema.TaggedError<DataApiExposed>("@replaceme/db/DataApiExposed")("DataApiExposed", {
  violations: Schema.Int,
}) {}

/**
 * A table is a violation when a Data API role can reach it but row security is off — the combination that turns a table
 * into a public endpoint. Either half alone is fine: no grant means PostgREST rejects the request before RLS matters,
 * and RLS without a grant is simply belt-and-braces.
 */
const findViolations = Effect.gen(function* () {
  const sql = yield* SqlClient.SqlClient

  return yield* sql<Violation>`
    SELECT n.nspname                       AS table_schema,
           c.relname                       AS table_name,
           g.grantee                       AS grantee,
           string_agg(DISTINCT g.privilege_type, ', ' ORDER BY g.privilege_type) AS privileges
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN information_schema.role_table_grants g
      ON g.table_schema = n.nspname AND g.table_name = c.relname
    WHERE ${sql.in("n.nspname", [...EXPOSED_SCHEMAS])}
      -- 'r' is an ordinary table; partitioned tables ('p') carry their own grants and are checked the same way.
      AND c.relkind IN ('r', 'p')
      AND g.grantee IN ('anon', 'authenticated')
      AND NOT c.relrowsecurity
    GROUP BY n.nspname, c.relname, g.grantee
    ORDER BY n.nspname, c.relname, g.grantee
  `
})

const program = findViolations.pipe(
  Effect.flatMap((violations) =>
    violations.length === 0
      ? Effect.logInfo(`No Data API exposure without RLS in ${EXPOSED_SCHEMAS.join(", ")}`)
      : Effect.logError(
          [
            `${violations.length} table(s) reachable by a Data API role with row security disabled:`,
            ...violations.map((v) => `  ${v.table_schema}.${v.table_name} → ${v.grantee} (${v.privileges})`),
            "",
            "Each one is readable with the project's publishable key. Fix by revoking the grant, or by enabling RLS",
            "and adding a policy that says what should be visible:",
            "",
            "  REVOKE ALL ON <table> FROM anon, authenticated;",
            "  -- or, to expose it deliberately:",
            "  ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;",
            "  CREATE POLICY <name> ON <table> FOR SELECT TO authenticated USING (<predicate>);",
            "  GRANT SELECT ON <table> TO authenticated;",
          ].join("\n"),
        ).pipe(Effect.andThen(Effect.fail(new DataApiExposed({ violations: violations.length })))),
  ),
  Effect.provide(PgAutoLive),
)

NodeRuntime.runMain(program)
