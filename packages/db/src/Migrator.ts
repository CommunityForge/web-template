/**
 * Schema ownership.
 *
 * The application's DDL is authored here, in TypeScript, and applied by Effect's `PgMigrator` rather than by the
 * Supabase CLI. GoTrue still owns `auth.*` and migrates it itself; nothing here touches that schema. The two coexist
 * because they write to different ledgers: this migrator's is `effect_sql_migrations` in `public`, Supabase's is
 * `supabase_migrations.schema_migrations`.
 *
 * The cost, so it is chosen rather than discovered: `supabase db reset` recreates `auth.*` and wipes `public`, taking
 * `effect_sql_migrations` with it, so the migrator must run after a reset. Two commands rather than one.
 *
 * `migrations` is a `fromRecord` loader rather than `fromFileSystem` so the migrations are ordinary imports: they are
 * typechecked by `tsc -b`, they survive bundling, and a renamed file is a compile error rather than a silently skipped
 * migration. Keys are `<id>_<name>` and are applied in id order. An applied migration is immutable; change the schema
 * by adding a file and a key.
 *
 * Every migration runs under `lock_timeout`. DDL such as `ALTER TABLE` queues for an `ACCESS EXCLUSIVE` lock, and every
 * query arriving behind it queues too, so a migration stuck behind one long-running query would stall the live
 * application for as long as that query runs. With the timeout, the migration fails instead, the migrator's single
 * transaction commits nothing, and a re-run retries it. The setting is `SET LOCAL` in effect, scoped to the migrator's
 * transaction, and is applied per migration rather than around the migrator ON PURPOSE: the migrator's first statement
 * on a fresh database is a probe that fails by design, which would abort any transaction opened around it. A migration
 * that knowingly needs a longer wait states its own `set_config('lock_timeout', ..., true)` first thing.
 *
 * @since 0.0.0
 */

import * as PgMigrator from "@effect/sql-pg/PgMigrator"
import * as Effect from "effect/Effect"
import * as Record from "effect/Record"
import * as Migrator from "effect/unstable/sql/Migrator"
import * as SqlClient from "effect/unstable/sql/SqlClient"

import * as DataApiLockdown from "./migrations/0001_data_api_lockdown.js"

/**
 * How long a migration's statement waits for a lock before it fails, as Postgres reads `lock_timeout`.
 *
 * @since 0.0.0
 * @category constants
 */
export const LOCK_TIMEOUT = "5s"

const underLockTimeout = (
  migration: Effect.Effect<void, unknown, SqlClient.SqlClient>,
): Effect.Effect<void, unknown, SqlClient.SqlClient> =>
  SqlClient.SqlClient.pipe(
    Effect.flatMap((sql) => sql`select set_config('lock_timeout', ${LOCK_TIMEOUT}, true)`),
    Effect.andThen(migration),
  )

/**
 * @since 0.0.0
 * @category loaders
 */
export const migrations: Migrator.Loader = Migrator.fromRecord(
  Record.map(
    {
      "0001_data_api_lockdown": DataApiLockdown.migration,
    },
    underLockTimeout,
  ),
)

/**
 * Runs pending migrations and reports which were applied.
 *
 * Requires `SqlClient`/`PgClient` plus `FileSystem`, `Path`, and a process spawner: `PgMigrator` declares those
 * unconditionally because of its optional `pg_dump` schema-dump support, so they must be provided even when
 * `schemaDirectory` is omitted.
 *
 * @since 0.0.0
 * @category constructors
 */
export const run = PgMigrator.run({ loader: migrations })

/**
 * The same, as a startup layer. Provides nothing, so it composes into an application's infrastructure rather than being
 * awaited by hand. For an application that legitimately owns its own database; an operator-run `bin/migrate.ts` is the
 * shape for a database several programs share.
 *
 * @since 0.0.0
 * @category layers
 */
export const layer = PgMigrator.layer({ loader: migrations })
