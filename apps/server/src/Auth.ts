/**
 * The provider binding: which issuer, audience and algorithms a bearer token is verified against, and how its claims
 * become a principal.
 *
 * @since 0.0.0
 */

import type * as TokenVerifier from "@landbank/domain/TokenVerifier"

import * as AuthMiddleware from "@landbank/domain/AuthMiddleware"
import * as SupabaseClaims from "@landbank/supabase/SupabaseClaims"
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Schema from "effect/Schema"

import * as JwksTokenVerifier from "./JwksTokenVerifier.js"

/**
 * @since 0.0.0
 * @category config
 */
export const SupabaseUrl: Config.Config<URL> = Config.schema(Schema.URLFromString, "PUBLIC_SUPABASE_URL")

/**
 * @since 0.0.0
 * @category layers
 */
export const TokenVerifierLive: Layer.Layer<TokenVerifier.TokenVerifier, Config.ConfigError> = Layer.unwrap(
  Effect.gen(function* () {
    const url = yield* SupabaseUrl
    return JwksTokenVerifier.layer({
      issuer: new URL(`${url.toString().replace(/\/$/, "")}/auth/v1`),
      /**
       * What Supabase stamps on a user token. Other audiences exist (OAuth clients get their own), and none of them are
       * this server.
       */
      audience: "authenticated",
      /**
       * Supabase's asymmetric signing keys are ECC P-256 or RSA; both spellings are named so a key rotation between
       * them does not need a code change, while symmetric algorithms stay excluded.
       */
      algorithms: ["ES256", "RS256"],
      /**
       * Nothing reads `app_metadata` yet, so it is accepted and left undecoded. Narrow this to a real schema at the
       * point a feature gates on an entitlement; the type flows through to `CurrentUser.AuthPrincipal`.
       */
      decode: SupabaseClaims.toPrincipal(Schema.Unknown),
    })
  }),
)

/**
 * @since 0.0.0
 * @category layers
 */
export const AuthLive: Layer.Layer<AuthMiddleware.AuthMiddleware, Config.ConfigError> = AuthMiddleware.layer.pipe(
  Layer.provide(TokenVerifierLive),
)
