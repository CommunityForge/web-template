import { describe, it } from "@effect/vitest"
import { assertTrue, deepStrictEqual, strictEqual } from "@effect/vitest/utils"
import * as Array from "effect/Array"
import * as Cause from "effect/Cause"
import * as Effect from "effect/Effect"
import * as Logger from "effect/Logger"
import * as MutableRef from "effect/MutableRef"
import * as References from "effect/References"
import * as HttpServerError from "effect/unstable/http/HttpServerError"
import * as HttpServerRequest from "effect/unstable/http/HttpServerRequest"
import * as HttpServerResponse from "effect/unstable/http/HttpServerResponse"

import * as Http from "../src/Http.js"

/**
 * One captured log line: the level, the cause, and the annotations as they stood when the line was written. Read inside
 * the logger ON PURPOSE: the annotations live on the fiber and are gone once the annotated effect returns.
 */
interface Entry {
  readonly logLevel: string
  readonly cause: Cause.Cause<unknown>
  readonly annotations: Readonly<Record<string, unknown>>
}

const request = HttpServerRequest.fromWeb(new Request("http://worker.test/api/boom?token=secret"))

/**
 * Runs `app` under `logFailures` with a capturing logger as the only logger and `Warn` as the minimum level, the level
 * a deployment runs at, and returns every line it wrote.
 */
const logged = <E>(app: Effect.Effect<HttpServerResponse.HttpServerResponse, E>) =>
  Effect.gen(function* () {
    const entries = MutableRef.make<ReadonlyArray<Entry>>([])
    const capture = Logger.make<unknown, void>((options) => {
      MutableRef.update(
        entries,
        Array.append({
          logLevel: options.logLevel,
          cause: options.cause,
          annotations: options.fiber.getRef(References.CurrentLogAnnotations),
        }),
      )
    })
    yield* Effect.exit(Http.logFailures(app)).pipe(
      Effect.provide(Logger.layer([capture])),
      Effect.provideService(References.MinimumLogLevel, "Warn"),
      Effect.provideService(HttpServerRequest.HttpServerRequest, request),
    )
    return MutableRef.get(entries)
  })

describe("Http", () => {
  it.effect("logFailures logs a dying handler once, at Error, with the request annotated", () =>
    Effect.gen(function* () {
      const defect = new Error("boom")
      const entries = yield* logged(Effect.die(defect))
      strictEqual(entries.length, 1)
      const [entry] = entries
      strictEqual(entry?.logLevel, "Error")
      assertTrue(entry !== undefined && Cause.hasDies(entry.cause))
      deepStrictEqual(entry?.annotations, { "http.method": "GET", "http.url": "/api/boom", "http.status": 500 })
    }),
  )

  it.effect("logFailures logs a failure that becomes a 500", () =>
    Effect.gen(function* () {
      const entries = yield* logged(
        Effect.fail(new HttpServerError.HttpServerError({ reason: new HttpServerError.InternalError({ request }) })),
      )
      strictEqual(entries.length, 1)
      strictEqual(entries[0]?.annotations["http.status"], 500)
    }),
  )

  it.effect("logFailures logs nothing for a failure that chooses a 4xx response", () =>
    Effect.gen(function* () {
      const entries = yield* logged(
        Effect.fail(new HttpServerError.HttpServerError({ reason: new HttpServerError.RouteNotFound({ request }) })),
      )
      strictEqual(entries.length, 0)
    }),
  )

  it.effect("logFailures logs nothing for a success", () =>
    Effect.gen(function* () {
      const entries = yield* logged(Effect.succeed(HttpServerResponse.empty({ status: 204 })))
      strictEqual(entries.length, 0)
    }),
  )

  it.effect("logFailures leaves the exit unchanged", () =>
    Effect.gen(function* () {
      const defect = new Error("boom")
      const cause = yield* Effect.exit(Effect.die(defect)).pipe(
        Effect.map((exit) => (exit._tag === "Failure" ? exit.cause : Cause.empty)),
      )
      const under = yield* Effect.exit(Http.logFailures(Effect.die(defect))).pipe(
        Effect.provide(Logger.layer([])),
        Effect.provideService(HttpServerRequest.HttpServerRequest, request),
        Effect.map((exit) => (exit._tag === "Failure" ? exit.cause : Cause.empty)),
      )
      deepStrictEqual(Cause.squash(under), Cause.squash(cause))
    }),
  )
})
