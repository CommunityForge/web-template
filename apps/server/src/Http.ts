/**
 * The composition root: one `HttpLive` layer that serves the API the domain declares.
 *
 * @since 0.0.0
 */

import * as NodeHttpServer from "@effect/platform-node/NodeHttpServer"
import * as Api from "@replaceme/domain/Api"
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as References from "effect/References"
import * as Schema from "effect/Schema"
import * as HttpMiddleware from "effect/unstable/http/HttpMiddleware"
import * as HttpRouter from "effect/unstable/http/HttpRouter"
import * as HttpServer from "effect/unstable/http/HttpServer"
import * as HttpApiBuilder from "effect/unstable/httpapi/HttpApiBuilder"
import * as HttpApiSwagger from "effect/unstable/httpapi/HttpApiSwagger"
import { createServer } from "node:http"

import { AuthLive } from "./Auth.js"
import * as TopLevelHttp from "./TopLevel/Http.js"

const withLogAddress = <A, E, R>(layer: Layer.Layer<A, E, R>): Layer.Layer<A, E, R | HttpServer.HttpServer> =>
  Layer.effectDiscard(
    HttpServer.addressFormattedWith((address) =>
      Effect.annotateLogs(Effect.logInfo(`Listening on: ${address}`), {
        docs: `${address}/docs`,
        "openapi.json": `${address}/openapi.json`,
      }),
    ),
  ).pipe(Layer.provideMerge(layer))

/**
 * No default: every launcher names its port, so an unset `API_PORT` is a broken deployment that refuses to start rather
 * than squatting on a guessed one.
 */
const ServerLive = NodeHttpServer.layerConfig(createServer, {
  port: Config.number("API_PORT"),
})

/**
 * `LOG_LEVEL` rather than a literal. Debug on a server that handles bearer tokens widens what a log aggregator ends up
 * holding, so the level is a deployment choice. No default: a missing one is a misconfigured environment better
 * surfaced at startup than papered over.
 */
const LoggerLive = Layer.unwrap(
  Effect.map(Config.logLevel("LOG_LEVEL"), (level) => Layer.succeed(References.MinimumLogLevel, level)),
)

/**
 * The API the domain declares, with every group's handlers provided and Swagger mounted at `/docs`.
 *
 * Coverage is type-checked: `HttpApiBuilder.layer(Api.Http)` requires the handler service of every group in the
 * `HttpApi`, so a group added to the contract and not provided here is an unsatisfied requirement `tsc -b` reports.
 *
 * @since 0.0.0
 * @category layers
 */
export const ApiLive = HttpApiBuilder.layer(Api.Http).pipe(
  Layer.provide(TopLevelHttp.HttpTopLevelLive),
  Layer.provide(HttpApiSwagger.layer(Api.Http)),
)

/**
 * The origins allowed to call this API, read from `APP_ORIGINS` as a comma-separated list.
 *
 * `HttpMiddleware.cors()` with no options allows every origin, which is what would let any page drive an authenticated
 * endpoint with a token it managed to read. `Config.Array` is the schema handed to `Config.schema`, not a `Config`
 * constructor. No default: an unset `APP_ORIGINS` should stop the server, not quietly reopen it.
 */
const AllowedOrigins: Config.Config<ReadonlyArray<string>> = Config.schema(Config.Array(Schema.String), "APP_ORIGINS")

/**
 * @since 0.0.0
 * @category layers
 */
export const HttpLive = Layer.unwrap(
  Effect.gen(function* () {
    const allowedOrigins = yield* AllowedOrigins

    return HttpRouter.serve(ApiLive, {
      middleware: HttpMiddleware.cors({ allowedOrigins, credentials: false }),
    })
  }),
).pipe(withLogAddress, Layer.provide(ServerLive), Layer.provide(AuthLive), Layer.provide(LoggerLive))
