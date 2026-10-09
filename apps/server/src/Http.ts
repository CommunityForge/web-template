/**
 * The portable half of the composition root: the API the domain declares, CORS around it, and the logger. Nothing here
 * names a runtime. `Node.ts` binds this to a listening port; `Worker.ts` turns it into a `fetch` handler.
 *
 * This module and everything it imports MUST stay free of `node:*` and `@effect/platform-node`: the Worker bundle is
 * built from it, and a Node import here would land in that bundle.
 *
 * @since 0.0.0
 */

import type * as HttpServerResponse from "effect/unstable/http/HttpServerResponse"

import * as Api from "@replaceme/domain/Api"
import * as Config from "effect/Config"
import * as Context from "effect/Context"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Option from "effect/Option"
import * as References from "effect/References"
import * as Schema from "effect/Schema"
import * as HttpMiddleware from "effect/unstable/http/HttpMiddleware"
import * as HttpRouter from "effect/unstable/http/HttpRouter"
import * as HttpServerError from "effect/unstable/http/HttpServerError"
import * as HttpServerRequest from "effect/unstable/http/HttpServerRequest"
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
 * The path of a request without its query and fragment, for a log line. A query can carry what a log aggregator should
 * not hold, so only the path is annotated.
 */
const pathOf = (request: HttpServerRequest.HttpServerRequest): string =>
  new URL(request.url, "http://localhost").pathname

/**
 * Logs the cause behind every response of status 500 or above, at Error level, annotated with the method, the path and
 * the status. Below 500 nothing is logged: a client error is the client's to read in its response. The response itself
 * is left exactly as the platform derives it, an empty body and never the cause.
 *
 * Error level ON PURPOSE: the platform's own request log is Info, so under the `Warn` a deployment runs at a dying
 * handler would otherwise leave no trace. The status is the one the platform will send, derived here the same way, so a
 * failure that chooses its own 4xx response is passed over and a bare defect is counted as the 500 it becomes.
 *
 * @since 0.0.0
 * @category middleware
 */
export const logFailures: <E, R>(
  app: Effect.Effect<HttpServerResponse.HttpServerResponse, E, HttpServerRequest.HttpServerRequest | R>,
) => Effect.Effect<HttpServerResponse.HttpServerResponse, E, HttpServerRequest.HttpServerRequest | R> =
  HttpMiddleware.make((app) =>
    Effect.withFiber((fiber) => {
      const request = Context.getUnsafe(fiber.context, HttpServerRequest.HttpServerRequest)
      return Effect.flatMap(Effect.exit(app), (exit) => {
        if (exit._tag === "Success") {
          return exit
        }
        const [, cause] = HttpServerError.causeResponseStripped(exit.cause)
        return Effect.flatMap(HttpServerError.causeResponse(exit.cause), ([response]) =>
          response.status < 500 || Option.isNone(cause)
            ? exit
            : Effect.andThen(
                Effect.annotateLogs(Effect.logError("Request failed", cause.value), {
                  "http.method": request.method,
                  "http.url": pathOf(request),
                  "http.status": response.status,
                }),
                exit,
              ),
        )
      })
    }),
  )

/**
 * `logFailures` installed on the router as GLOBAL middleware, so a failure in any route is logged whichever entry point
 * serves it.
 *
 * @since 0.0.0
 * @category layers
 */
export const FailureLogLive = HttpRouter.middleware(logFailures, { global: true })

/**
 * The API the domain declares, with every group's handlers provided, CORS and failure logging around every route, the
 * OpenAPI document at `/api/openapi.json` and Swagger at `/api/docs`. The two documents sit beside the contract's
 * `/api` prefix rather than under it: the builder mounts them on the router directly, so the prefix is spelled here.
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
  FailureLogLive,
)
