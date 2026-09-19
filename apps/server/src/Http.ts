/**
 * The portable half of the composition root: the API the domain declares, CORS around it, and the logger. Nothing here
 * names a runtime. `Node.ts` binds this to a listening port; `Worker.ts` turns it into a `fetch` handler.
 *
 * This module and everything it imports MUST stay free of `node:*` and `@effect/platform-node`: the Worker bundle is
 * built from it, and a Node import here would land in that bundle.
 *
 * @since 0.0.0
 */

import * as Api from "@replaceme/domain/Api"
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as References from "effect/References"
import * as Schema from "effect/Schema"
import * as HttpMiddleware from "effect/unstable/http/HttpMiddleware"
import * as HttpRouter from "effect/unstable/http/HttpRouter"
import * as HttpApiBuilder from "effect/unstable/httpapi/HttpApiBuilder"
import * as HttpApiSwagger from "effect/unstable/httpapi/HttpApiSwagger"

import * as TopLevelHttp from "./TopLevel/Http.js"

/**
 * `LOG_LEVEL` rather than a literal. Debug on a server that handles bearer tokens widens what a log aggregator ends up
 * holding, so the level is a deployment choice. No default: a missing one is a misconfigured environment better
 * surfaced at startup than papered over.
 *
 * @since 0.0.0
 * @category layers
 */
export const LoggerLive: Layer.Layer<never, Config.ConfigError> = Layer.unwrap(
  Effect.map(Config.LogLevel("LOG_LEVEL"), (level) => Layer.succeed(References.MinimumLogLevel, level)),
)

/**
 * The origins allowed to call this API, read from `APP_ORIGINS` as a comma-separated list.
 *
 * `HttpMiddleware.cors()` with no options allows every origin, which is what would let any page drive an authenticated
 * endpoint with a token it managed to read. No default: an unset `APP_ORIGINS` should stop the server, not quietly
 * reopen it.
 *
 * @since 0.0.0
 * @category config
 */
export const AllowedOrigins: Config.Config<ReadonlyArray<string>> = Config.Array(Schema.String, "APP_ORIGINS")

/**
 * The CORS policy over `AllowedOrigins`, installed on the router as GLOBAL middleware so it runs around every route.
 *
 * A router middleware, not the `middleware` option of `HttpRouter.serve` / `toWebHandler`: that option wraps the whole
 * chain INCLUDING the send, so headers a middleware adds there never reach the client. CORS adds headers.
 *
 * @since 0.0.0
 * @category layers
 */
export const CorsLive = HttpRouter.middleware(
  Effect.map(AllowedOrigins, (allowedOrigins) => {
    const cors = HttpMiddleware.cors({ allowedOrigins, credentials: false })
    return (app) => cors(app)
  }),
  { global: true },
)

/**
 * The API the domain declares, with every group's handlers provided, CORS around every route, the OpenAPI document at
 * `/api/openapi.json` and Swagger at `/api/docs`. The two documents sit beside the contract's `/api` prefix rather than
 * under it: the builder mounts them on the router directly, so the prefix is spelled here.
 *
 * Coverage is type-checked: `HttpApiBuilder.layer(Api.Http)` requires the handler service of every group in the
 * `HttpApi`, so a group added to the contract and not provided here is an unsatisfied requirement `tsc -b` reports.
 *
 * The Swagger layer inlines its UI, about a megabyte of JavaScript, into every build that carries this layer.
 *
 * @since 0.0.0
 * @category layers
 */
export const ApiLive = Layer.mergeAll(
  HttpApiBuilder.layer(Api.Http, { openapiPath: "/api/openapi.json" }).pipe(
    Layer.provide(TopLevelHttp.HttpTopLevelLive),
    Layer.provide(HttpApiSwagger.layer(Api.Http, { path: "/api/docs" })),
  ),
  CorsLive,
)
