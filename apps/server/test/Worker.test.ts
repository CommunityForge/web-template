import { describe, it } from "@effect/vitest"
import { assertTrue, strictEqual } from "@effect/vitest/utils"
import * as Effect from "effect/Effect"
import * as Predicate from "effect/Predicate"

import * as Worker from "../src/Worker.js"

/**
 * A fake environment shaped like a deployment's: the three required vars, a `DB_URL` no request here ever connects to,
 * and a binding the Worker does not read. No database is needed because no route queries one. Two origins, because the
 * CORS middleware only consults the allow-list when there is more than one.
 */
const env = {
  PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  LOG_LEVEL: "None",
  APP_ORIGINS: "http://localhost:5173,http://127.0.0.1:5173",
  DB_URL: "postgres://postgres:postgres@127.0.0.1:54322/postgres",
  ASSETS: {},
}

type Handler = (request: Request) => Promise<Response>

const withHandler =
  (bindings: object) =>
  <A, E>(use: (handler: Handler) => Effect.Effect<A, E>) =>
    Effect.acquireUseRelease(
      Effect.sync(() => Worker.make(bindings)),
      ({ handler }) => use(handler),
      ({ dispose }) => Effect.promise(dispose),
    )

const get = (handler: Handler, path: string, init?: RequestInit) =>
  Effect.promise(() => handler(new Request(`http://worker.test${path}`, init)))

const getTagged = (handler: Handler, path: string) =>
  Effect.tryPromise({
    try: () => handler(new Request(`http://worker.test${path}`)),
    catch: (cause): string =>
      Predicate.hasProperty(cause, "_tag") && Predicate.isString(cause._tag) ? cause._tag : String(cause),
  })

describe("Worker", () => {
  it.effect("GET /api/health answers", () =>
    withHandler(env)((handler) =>
      Effect.gen(function* () {
        const response = yield* get(handler, "/api/health")
        strictEqual(response.status, 204)
      }),
    ),
  )

  it.effect("CORS admits an allowed origin on the response and nothing else", () =>
    withHandler(env)((handler) =>
      Effect.gen(function* () {
        const allowed = yield* get(handler, "/api/health", { headers: { origin: "http://127.0.0.1:5173" } })
        strictEqual(allowed.headers.get("access-control-allow-origin"), "http://127.0.0.1:5173")
        const other = yield* get(handler, "/api/health", { headers: { origin: "http://elsewhere.test" } })
        strictEqual(other.headers.get("access-control-allow-origin"), null)
      }),
    ),
  )

  it.effect("GET /api/docs serves Swagger", () =>
    withHandler(env)((handler) =>
      Effect.gen(function* () {
        const response = yield* get(handler, "/api/docs")
        strictEqual(response.status, 200)
        assertTrue(response.headers.get("content-type")?.startsWith("text/html"))
      }),
    ),
  )

  it.effect("GET /api/openapi.json serves the document", () =>
    withHandler(env)((handler) =>
      Effect.gen(function* () {
        const response = yield* get(handler, "/api/openapi.json")
        strictEqual(response.status, 200)
        const body: unknown = yield* Effect.promise(() => response.json())
        assertTrue(Predicate.hasProperty(body, "openapi"))
      }),
    ),
  )

  it.effect("DB_URL resolves to the Hyperdrive binding when only the binding is bound", () =>
    Effect.gen(function* () {
      const provider = Worker.configProvider({
        HYPERDRIVE: { connectionString: "postgres://hyperdrive.test/postgres" },
      })
      const node = yield* provider.load(["DB_URL"])
      strictEqual(node?._tag === "Value" ? node.value : undefined, "postgres://hyperdrive.test/postgres")
    }),
  )

  it.effect("DB_URL resolves to the var when only the var is set", () =>
    Effect.gen(function* () {
      const provider = Worker.configProvider({ DB_URL: "postgres://branch.test/postgres" })
      const node = yield* provider.load(["DB_URL"])
      strictEqual(node?._tag === "Value" ? node.value : undefined, "postgres://branch.test/postgres")
    }),
  )

  it.effect("the Hyperdrive binding wins over DB_URL when both are present", () =>
    Effect.gen(function* () {
      const provider = Worker.configProvider({
        DB_URL: "postgres://branch.test/postgres",
        HYPERDRIVE: { connectionString: "postgres://hyperdrive.test/postgres" },
      })
      const node = yield* provider.load(["DB_URL"])
      strictEqual(node?._tag === "Value" ? node.value : undefined, "postgres://hyperdrive.test/postgres")
    }),
  )

  it.effect("the Hyperdrive binding answers DB_URL alone, never another key", () =>
    Effect.gen(function* () {
      const provider = Worker.configProvider({
        LOG_LEVEL: "Warn",
        HYPERDRIVE: { connectionString: "postgres://hyperdrive.test/postgres" },
      })
      const node = yield* provider.load(["LOG_LEVEL"])
      strictEqual(node?._tag === "Value" ? node.value : undefined, "Warn")
    }),
  )

  it.effect("a missing PUBLIC_SUPABASE_URL fails the first request with a ConfigError", () =>
    withHandler({ LOG_LEVEL: env.LOG_LEVEL, APP_ORIGINS: env.APP_ORIGINS, DB_URL: env.DB_URL })((handler) =>
      Effect.gen(function* () {
        const error = yield* Effect.flip(getTagged(handler, "/api/health"))
        strictEqual(error, "ConfigError")
      }),
    ),
  )
})
