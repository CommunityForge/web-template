/**
 * The Node entry point's half of the composition root: the portable API bound to a listening port.
 *
 * With `main.ts`, this is the ONLY module that may import `node:*` or `@effect/platform-node`.
 *
 * @since 0.0.0
 */

import * as NodeHttpServer from "@effect/platform-node/NodeHttpServer"
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as HttpRouter from "effect/unstable/http/HttpRouter"
import * as HttpServer from "effect/unstable/http/HttpServer"
import * as NodeHttp from "node:http"

import * as Auth from "./Auth.js"
import * as Http from "./Http.js"

const withLogAddress = <A, E, R>(layer: Layer.Layer<A, E, R>): Layer.Layer<A, E, R | HttpServer.HttpServer> =>
  Layer.effectDiscard(
    HttpServer.addressFormattedWith((address) =>
      Effect.annotateLogs(Effect.logInfo(`Listening on: ${address}`), {
        docs: `${address}/api/docs`,
        "openapi.json": `${address}/api/openapi.json`,
      }),
    ),
  ).pipe(Layer.provideMerge(layer))

/**
 * No default: every launcher names its port, so an unset `API_PORT` is a broken deployment that refuses to start rather
 * than squatting on a guessed one.
 *
 * @since 0.0.0
 * @category layers
 */
export const ServerLive = NodeHttpServer.layerConfig(NodeHttp.createServer, {
  port: Config.Port("API_PORT"),
})

/**
 * @since 0.0.0
 * @category layers
 */
export const HttpLive = HttpRouter.serve(Http.ApiLive).pipe(
  withLogAddress,
  Layer.provide(ServerLive),
  Layer.provide(Auth.AuthLive),
  Layer.provide(Http.LoggerLive),
)
