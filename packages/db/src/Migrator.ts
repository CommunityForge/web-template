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
 * @since 0.0.0
 */

import * as PgMigrator from "@effect/sql-pg/PgMigrator"
import * as Migrator from "effect/unstable/sql/Migrator"

import * as DataApiLockdown from "./migrations/0001_data_api_lockdown.js"

/**
 * @since 0.0.0
 * @category loaders
 */
export const migrations: Migrator.Loader = Migrator.fromRecord({
  "0001_data_api_lockdown": DataApiLockdown.migration,
})

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
