/**
 * JWKS-based implementation of the `TokenVerifier` service.
 *
 * @since 0.0.0
 */

import type * as CurrentUser from "@replaceme/domain/CurrentUser"

import * as Auth from "@replaceme/domain/Auth"
import * as TokenVerifier from "@replaceme/domain/TokenVerifier"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Redacted from "effect/Redacted"
import { createRemoteJWKSet, jwtVerify } from "jose"

/**
 * @since 0.0.0
 * @category models
 */
export interface JwksTokenVerifierOptions {
  /**
   * Expected `iss` claim
   */
  readonly issuer: URL

  /**
   * Expected `aud` claim.
   *
   * Supabase issues `aud: "authenticated"` for user tokens and can mint other audiences for OAuth clients, so without
   * this every token the project ever signs is accepted here. Passing it also makes `aud` a required claim in `jose`.
   */
  readonly audience: string

  /**
   * Accepted JWS algorithms.
   *
   * `jose` otherwise accepts every algorithm the resolved key supports. Naming them keeps the set from widening
   * silently if the project's signing keys change.
   */
  readonly algorithms: ReadonlyArray<string>

  /**
   * JWKS endpoint
   */
  readonly jwks?: URL

  /**
   * Monomorphism from provider claim to domain principal
   */
  readonly decode: (claims: unknown) => Effect.Effect<CurrentUser.AuthPrincipal, Auth.Unauthorized>
}

/**
 * @since 0.0.0
 * @category constructors
 */
export const make = (options: JwksTokenVerifierOptions): TokenVerifier.TokenVerifierService => {
  const jwks = createRemoteJWKSet(
    options.jwks ?? new URL(`${options.issuer.toString().replace(/\/$/, "")}/.well-known/jwks.json`),
  )

  return {
    verify: (credential) =>
      Effect.tryPromise({
        try: () =>
          jwtVerify(Redacted.value(credential), jwks, {
            issuer: options.issuer.toString().replace(/\/$/, ""),
            audience: options.audience,
            algorithms: [...options.algorithms],
          }),
        /**
         * Signature, expiry, audience, and issuer failures are opaque by design.
         */
        catch: () => new Auth.Unauthorized(),
      }).pipe(Effect.flatMap(({ payload }) => options.decode(payload))),
  }
}

/**
 * @since 0.0.0
 * @category layers
 */
export const layer = (options: JwksTokenVerifierOptions): Layer.Layer<TokenVerifier.TokenVerifier> =>
  Layer.sync(TokenVerifier.TokenVerifier, () => make(options))
