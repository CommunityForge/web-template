/**
 * The Cloudflare Worker entry point: the portable API as a `fetch` handler. The platform serves the SPA's static assets
 * beside it and hands this module only what its config routes here.
 *
 * Nothing here touches Node. `HttpServer.layerServices` stands in for the platform layer a Node server gets from
 * `NodeHttpServer`: pure JavaScript with a no-op `FileSystem`. Upstream tags it for testing; it is used here ON
 * PURPOSE, because no route serves a file.
 *
 * The `SqlClient` layer is REQUEST-scoped. `SqlRequestLive` installs it as global router middleware that builds the
 * client fresh for every request (`local: true`, so no memo map is consulted) and tears it down with the request. A
 * Workers socket opened in one request may not be used by another, so the database layer is the one layer never
 * memoized across requests; auth, logger and handlers are built once per isolate.
 *
 * Configuration is the Worker `env`, read through a `ConfigProvider` the layers consult as they build. `DB_URL` wins
 * over the `HYPERDRIVE` binding ON PURPOSE: a preview version inherits the production config, binding included, and the
 * var is what points a preview at a database of its own. A missing value fails the first request with a `ConfigError`
 * naming it: the Worker's form of refusing to start.
 *
 * @since 0.0.0
 */

import * as ConfigProvider from "effect/ConfigProvider"
import * as Effect from "effect/Effect"
import * as Function from "effect/Function"
import * as Layer from "effect/Layer"
import * as Predicate from "effect/Predicate"
import * as HttpRouter from "effect/unstable/http/HttpRouter"
import * as HttpServer from "effect/unstable/http/HttpServer"

import * as Auth from "./Auth.js"
import * as Http from "./Http.js"
import * as Sql from "./Sql.js"

/**
 * `SqlClient` for exactly one request: `Sql.PgUrlLive` built inside the request, around the route, and closed with it.
 * Global, so every route sees it; typed as PROVIDING the client, so a route that requires `SqlClient` is satisfied by
 * this layer and nothing else has to name a database.
 *
 * @since 0.0.0
 * @category layers
 */
export const SqlRequestLive = HttpRouter.middleware<{ provides: Layer.Success<typeof Sql.PgUrlLive> }>()(
  (app) => Effect.provide(app, Sql.PgUrlLive, { local: true }),
  { global: true },
)

/**
 * The Hyperdrive binding's connection string, as a provider answering `DB_URL` and nothing else. Read by property
 * access rather than by walking `env`: the binding is a platform object whose fields are not own keys.
 */
const fromHyperdrive = (env: object): ConfigProvider.ConfigProvider =>
  Predicate.hasProperty(env, "HYPERDRIVE") && Predicate.hasProperty(env.HYPERDRIVE, "connectionString")
    ? ConfigProvider.fromUnknown({ DB_URL: env.HYPERDRIVE.connectionString })
    : ConfigProvider.fromUnknown({})

/**
 * The Worker's `env` as the layers' `ConfigProvider`: the vars themselves first, the Hyperdrive binding as the fallback
 * for `DB_URL`.
 *
 * @since 0.0.0
 * @category config
 */
export const configProvider = (env: object): ConfigProvider.ConfigProvider =>
  ConfigProvider.orElse(ConfigProvider.fromUnknown(env), fromHyperdrive(env))

/**
 * The app layer for one `env`. Everything a request must see (the log level, the config provider, the auth middleware,
 * the platform services) is MERGED in: request fibers in a web handler run under the built context and nothing else, so
 * an input to the build is not enough.
 *
 * @since 0.0.0
 * @category layers
 */
export const AppLive = (env: object) =>
  Layer.mergeAll(Http.ApiLive, SqlRequestLive).pipe(
    Layer.provideMerge(HttpServer.layerServices),
    Layer.provideMerge(Auth.AuthLive),
    Layer.provideMerge(Http.LoggerLive),
    Layer.provideMerge(ConfigProvider.layer(configProvider(env))),
  )

/**
 * The web handler for one `env`. The layer builds on the first request and is reused until `dispose`.
 *
 * @since 0.0.0
 * @category constructors
 */
export const make = (env: object) => HttpRouter.toWebHandler(AppLive(env))

/**
 * One handler per isolate: `env` is fixed for an isolate's life, so it is the memo key. A build that fails stays
 * failed, and every request reports the same cause.
 */
const handlerFor = Function.memoize(make)

/**
 * The module Workers loads. A default export is the platform's contract for a Worker module, and this unit's one
 * exception to exporting by name.
 *
 * @since 0.0.0
 * @category entry point
 */
export default {
  fetch: (request: Request, env: object): Promise<Response> => handlerFor(env).handler(request),
}
