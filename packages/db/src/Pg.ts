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
 * ## Driver contract
 *
 * The client speaks the wire protocol itself: prepared statements are NAMED by default (`prepare: false` is the knob a
 * transaction-mode pooler needs), and `timestamp` / `timestamptz` columns decode to `Date`. Every column arrives in
 * BINARY format, and a type without a registered codec is read as UTF-8 text, so a binary value whose bytes are not
 * valid UTF-8 fails the row. `regclass` has no built-in codec, and the migrator's own table probe (`select
 * 'effect_sql_migrations'::regclass`) returns one: a table OID with a high byte set would fail every migration run.
 * `types` closes that gap and is the registry `PgLive` is built with.
 *
 * @since 0.0.0
 */

import * as PgClient from "@effect/sql-pg/PgClient"
import * as PgTypes from "@effect/sql-pg/PgTypes"
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Option from "effect/Option"
import * as Result from "effect/Result"

/**
 * The OID of Postgres's `regclass` type. Its binary representation is the referenced relation's OID: four bytes,
 * unsigned, big-endian, exactly like `oid` itself.
 *
 * @since 0.0.0
 * @category types
 */
export const REGCLASS_OID = 2205

const OID_MAX = 4294967295

const isOid = (value: unknown): value is number =>
  typeof value === "number" && globalThis.Number.isInteger(value) && value >= 0 && value <= OID_MAX

const regclass: PgTypes.Codec<number> = {
  decode: (bytes) =>
    bytes.byteLength === 4
      ? Result.succeed(new DataView(bytes.buffer, bytes.byteOffset, 4).getUint32(0))
      : Result.fail(
          new PgTypes.CodecError({ message: `Expected 4 byte(s) for regclass, received ${bytes.byteLength}` }),
        ),
  encode: (value) =>
    isOid(value)
      ? Result.succeed(Uint8Array.of(value >>> 24, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff))
      : Result.fail(
          new PgTypes.CodecError({
            message: `Expected an integer between 0 and ${OID_MAX} for regclass, received ${String(value)}`,
          }),
        ),
}

const withRegclass = (registry: PgTypes.Registry): PgTypes.Registry => {
  registry.register(REGCLASS_OID, regclass)
  return registry
}

/**
 * The driver's built-in codecs plus `regclass`.
 *
 * @since 0.0.0
 * @category types
 */
export const types: PgTypes.Registry = withRegclass(PgTypes.makeRegistry())

/**
 * @since 0.0.0
 * @category config
 */
export const config = {
  host: Config.String("DB_HOST"),
  port: Config.Port("DB_PORT"),
  username: Config.String("DB_USER"),
  password: Config.Redacted("DB_PASSWD"),
  database: Config.String("DB_DATABASE"),
  types: Config.succeed(types),
} as const

/**
 * Provides `SqlClient` (and `PgClient`) against the configured Postgres.
 *
 * @since 0.0.0
 * @category layers
 */
export const PgLive = PgClient.layerConfig(config)

/**
 * The single-variable form: one `DB_URL` connection string, as a pooler or a connection proxy hands it out.
 *
 * @since 0.0.0
 * @category config
 */
export const urlConfig = {
  url: Config.Redacted("DB_URL"),
  types: Config.succeed(types),
} as const

/**
 * Provides `SqlClient` (and `PgClient`) against the Postgres `DB_URL` names.
 *
 * Prepared statements stay NAMED here, exactly as in `PgLive`. The string therefore has to point at something that
 * preserves them across statements on one connection: a SESSION-mode pooler or a connection proxy that pins the
 * backend, never a transaction-mode pooler (Supabase's port 6543), which would answer a later statement from a
 * different backend that never saw the `PREPARE`.
 *
 * @since 0.0.0
 * @category layers
 */
export const PgUrlLive = PgClient.layerConfig(urlConfig)

/**
 * `PgUrlLive` when `DB_URL` is set, `PgLive` otherwise: the shape an operator program takes, so one binary runs against
 * local Supabase's five `DB_*` values and against a hosted branch's single connection string alike.
 *
 * `DB_URL` wins whenever it is present; the five parts are never consulted then, so a stale `DB_HOST` beside a `DB_URL`
 * is inert rather than a second candidate.
 *
 * @since 0.0.0
 * @category layers
 */
export const PgAutoLive = Layer.unwrap(
  Effect.gen(function* () {
    const url = yield* Config.option(Config.Redacted("DB_URL"))
    return Option.isSome(url) ? PgUrlLive : PgLive
  }),
)
