/**
 * Apply pending migrations, then exit.
 *
 * The entry point behind `nix run .#db-migrate`. It is a program rather than a startup layer on the server because
 * migration is an operational boundary, not something an application does on its way up — two applications share this
 * database, and neither should race the other to migrate it. Nothing on a request path may reach this program: it is
 * invoked by an operator, and applying DDL is never a consequence of serving a request.
 *
 * `supabase db reset` recreates `auth.*` and wipes `public` — including `effect_sql_migrations` — so this must run
 * after any reset. That is the standing cost of Effect owning the DDL rather than the Supabase CLI, and it is why this
 * exists as its own command.
 *
 * Configuration comes from the ambient `ConfigProvider`: one `DB_URL` connection string when set (a hosted database's
 * SESSION-mode pooler, never the transaction pooler), else `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWD`/`DB_DATABASE`.
 * Nothing here has a default; the launcher names every value.
 *
 * This file is also bundled to `build/migrate.js`, one self-contained module importing only `node:*`, which is how it
 * runs where no workspace is installed.
 *
 * @since 0.0.0
 */

import * as NodeRuntime from "@effect/platform-node/NodeRuntime"
import * as NodeServices from "@effect/platform-node/NodeServices"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"

import { run } from "../Migrator.js"
import { PgAutoLive } from "../Pg.js"

const MigratorServices = Layer.mergeAll(PgAutoLive, NodeServices.layer)

const program = run.pipe(
  Effect.tap((applied) =>
    applied.length === 0
      ? Effect.logInfo("No pending migrations")
      : Effect.logInfo(
          `Applied ${applied.length} migration(s): ${applied.map(([id, name]) => `${id}_${name}`).join(", ")}`,
        ),
  ),
  Effect.provide(MigratorServices),
)

NodeRuntime.runMain(program)
