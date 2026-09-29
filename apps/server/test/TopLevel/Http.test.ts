import { layer } from "@effect/vitest"
import * as Api from "@landbank/domain/Api"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as HttpServer from "effect/unstable/http/HttpServer"
import * as HttpApiTest from "effect/unstable/httpapi/HttpApiTest"

import * as TopLevelHttp from "../../src/TopLevel/Http.js"

/**
 * The group's handlers behind an in-memory typed client: the same request encoding, routing and response decoding a
 * real server and client would use, with no port bound. A dependency the handlers need (a repository, a token verifier)
 * is swapped for a stub layer here rather than mocked.
 */
const makeClient = HttpApiTest.groups(Api.Http, ["topLevel"])

layer(Layer.mergeAll(TopLevelHttp.HttpTopLevelLive, HttpServer.layerServices))("TopLevel", (it) => {
  it.effect("health answers", () =>
    Effect.gen(function* () {
      const client = yield* makeClient
      yield* client.health()
    }),
  )
})
