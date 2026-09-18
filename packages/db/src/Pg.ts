/**
 * The Postgres client layer, in one place.
 *
 * Configuration is looked up through the ambient `ConfigProvider` rather than passed in, so a layer that needs the
 * database declares no extra requirement and the deployment decides the values.
 *
 * ## No defaults
 *
 * A missing credential stops the process rather than quietly authenticating with a development fallback. The deployment
 * supplies every value; nothing here should acquire a `withDefault`.
 *
 * @since 0.0.0
 */

import * as PgClient from "@effect/sql-pg/PgClient"
import * as Config from "effect/Config"

/**
 * @since 0.0.0
 * @category config
 */
export const config = {
  host: Config.string("DB_HOST"),
  port: Config.port("DB_PORT"),
  username: Config.string("DB_USER"),
  password: Config.redacted("DB_PASSWD"),
  database: Config.string("DB_DATABASE"),
} as const

/**
 * Provides `SqlClient` (and `PgClient`) against the configured Postgres.
 *
 * @since 0.0.0
 * @category layers
 */
export const PgLive = PgClient.layerConfig(config)
