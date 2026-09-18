/**
 * Bearer-token authentication middleware for the HttpApi.
 *
 * The server layer depends only on the `TokenVerifier` service and the client layer only on the `Auth` service, so each
 * is written once here and a mechanism or provider swap touches one layer at a composition root.
 *
 * @since 0.0.0
 */

import type * as Context from "effect/Context"

import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as HttpClientRequest from "effect/unstable/http/HttpClientRequest"
import * as HttpApiMiddleware from "effect/unstable/httpapi/HttpApiMiddleware"
import * as HttpApiSecurity from "effect/unstable/httpapi/HttpApiSecurity"

import * as Auth from "./Auth.js"
import * as CurrentUser from "./CurrentUser.js"
import * as TokenVerifier from "./TokenVerifier.js"

/**
 * Bearer-token security middleware for the HttpApi.
 *
 * @since 0.0.0
 * @category middleware
 */
export class AuthMiddleware extends HttpApiMiddleware.Service<
  AuthMiddleware,
  {
    provides: CurrentUser.CurrentUser
    clientError: Auth.Unauthorized
  }
>()("@replaceme/domain/AuthMiddleware", {
  error: Auth.Unauthorized,
  security: { bearer: HttpApiSecurity.bearer },
  requiredForClient: true,
}) {}

/**
 * Run a handler under the verified principal, with `userId` and `isAnonymous` on both the span and the log context.
 *
 * `email` is deliberately absent: traces and logs are exported and retained more widely than the database. The
 * annotation runs BEFORE the handler so a request that fails still carries the identity a support report is looked up
 * by.
 */
const withPrincipal = <A, E, R>(
  effect: Effect.Effect<A, E, R>,
  principal: CurrentUser.AuthPrincipal,
): Effect.Effect<A, E, Exclude<R, CurrentUser.CurrentUser>> => {
  const identity = { userId: principal.userId, isAnonymous: CurrentUser.isAnonymous(principal) }
  return Effect.annotateCurrentSpan(identity).pipe(
    Effect.andThen(Effect.provideService(effect, CurrentUser.CurrentUser, principal)),
    Effect.annotateLogs(identity),
  )
}

/**
 * Server implementation of {@link AuthMiddleware}.
 *
 * @since 0.0.0
 * @category layers
 */
export const layer: Layer.Layer<AuthMiddleware, never, TokenVerifier.TokenVerifier> = Layer.effect(
  AuthMiddleware,
  Effect.gen(function* () {
    const verifier = yield* TokenVerifier.TokenVerifier
    return {
      bearer: (httpEffect, { credential }) =>
        Effect.flatMap(verifier.verify(credential), (principal) => withPrincipal(httpEffect, principal)),
    } satisfies Context.Service.Shape<typeof AuthMiddleware>
  }),
)

/**
 * Client implementation of {@link AuthMiddleware}.
 *
 * @since 0.0.0
 * @category layers
 */
export const layerClient: Layer.Layer<
  HttpApiMiddleware.ForClient<AuthMiddleware>,
  never,
  Auth.Auth
> = HttpApiMiddleware.layerClient(
  AuthMiddleware,
  Effect.gen(function* () {
    const auth = yield* Auth.Auth
    return ({ next, request }) =>
      Effect.flatMap(auth.accessToken, (token) => next(HttpClientRequest.bearerToken(request, token)))
  }),
)
