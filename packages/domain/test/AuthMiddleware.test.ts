import { layer } from "@effect/vitest"
import { strictEqual } from "@effect/vitest/utils"
import * as Auth from "@landbank/domain/Auth"
import * as AuthMiddleware from "@landbank/domain/AuthMiddleware"
import * as CurrentUser from "@landbank/domain/CurrentUser"
import * as TokenVerifier from "@landbank/domain/TokenVerifier"
import * as User from "@landbank/domain/User"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Option from "effect/Option"
import * as Redacted from "effect/Redacted"
import * as Schema from "effect/Schema"
import * as HttpClientRequest from "effect/unstable/http/HttpClientRequest"
import * as HttpServer from "effect/unstable/http/HttpServer"
import * as HttpApi from "effect/unstable/httpapi/HttpApi"
import * as HttpApiBuilder from "effect/unstable/httpapi/HttpApiBuilder"
import * as HttpApiEndpoint from "effect/unstable/httpapi/HttpApiEndpoint"
import * as HttpApiGroup from "effect/unstable/httpapi/HttpApiGroup"
import * as HttpApiMiddleware from "effect/unstable/httpapi/HttpApiMiddleware"
import * as HttpApiTest from "effect/unstable/httpapi/HttpApiTest"

/**
 * The smallest API an authenticated group can be: one endpoint that reports who the middleware said is calling.
 */
const Whoami = Schema.Struct({ userId: User.UserId, isAnonymous: Schema.Boolean })

class MeApi extends HttpApiGroup.make("me")
  .add(HttpApiEndpoint.get("whoami", "/me", { success: Whoami }))
  .middleware(AuthMiddleware.AuthMiddleware) {}

const Api = HttpApi.make("test").add(MeApi)

const MeLive = HttpApiBuilder.group(Api, "me", (handlers) =>
  handlers.handle("whoami", () =>
    Effect.map(Effect.service(CurrentUser.CurrentUser), (principal) => ({
      userId: principal.userId,
      isAnonymous: CurrentUser.isAnonymous(principal),
    })),
  ),
)

const userId = Schema.decodeSync(User.UserId)("8d2b1a6e-5f0c-4c3a-9d7e-2b1f0a9c8d7e")

const member = CurrentUser.AuthPrincipal.Member({
  userId,
  email: Option.some("member@example.com"),
  appMetadata: Option.none(),
})

/**
 * The seam, swapped: one credential is accepted and every other one is refused. No JWKS, no network.
 */
const StubVerifier = Layer.succeed(TokenVerifier.TokenVerifier, {
  verify: (credential) =>
    Redacted.value(credential) === "valid-token" ? Effect.succeed(member) : Effect.fail(new Auth.Unauthorized()),
})

const withBearer = (token: string) =>
  HttpApiMiddleware.layerClient(AuthMiddleware.AuthMiddleware, ({ next, request }) =>
    next(HttpClientRequest.bearerToken(request, token)),
  )

const withoutBearer = HttpApiMiddleware.layerClient(AuthMiddleware.AuthMiddleware, ({ next, request }) => next(request))

const makeClient = HttpApiTest.groups(Api, ["me"])

/**
 * The group layer resolves its middleware while the routes are built, so the middleware is provided TO the group layer
 * (and merged, because the in-memory client resolves it again) rather than placed beside it.
 */
const MeTest = MeLive.pipe(
  Layer.provideMerge(AuthMiddleware.layer.pipe(Layer.provide(StubVerifier))),
  Layer.provideMerge(HttpServer.layerServices),
)

layer(MeTest)("AuthMiddleware", (it) => {
  it.effect("a request without a bearer token is Unauthorized", () =>
    Effect.gen(function* () {
      const client = yield* makeClient
      const error = yield* Effect.flip(client.me.whoami())
      strictEqual(error._tag, "Unauthorized")
    }).pipe(Effect.provide(withoutBearer)),
  )

  it.effect("a request with a refused bearer token is Unauthorized", () =>
    Effect.gen(function* () {
      const client = yield* makeClient
      const error = yield* Effect.flip(client.me.whoami())
      strictEqual(error._tag, "Unauthorized")
    }).pipe(Effect.provide(withBearer("forged-token"))),
  )

  it.effect("a request with an accepted bearer token reaches the handler as the verified principal", () =>
    Effect.gen(function* () {
      const client = yield* makeClient
      const whoami = yield* client.me.whoami()
      strictEqual(whoami.userId, userId)
      strictEqual(whoami.isAnonymous, false)
    }).pipe(Effect.provide(withBearer("valid-token"))),
  )
})
