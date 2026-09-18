/**
 * The server-side authentication service.
 *
 * The smallest seam that varies by auth _mechanism_: an opaque credential in, a principal out. JWT verification, a
 * session-store lookup, or an API-key table are all implementations of this one function. The HttpApi auth middleware
 * layer is written once against this service, so a provider/mechanism swap touches exactly one layer at the server's
 * composition root.
 *
 * @since 0.0.0
 */

import type * as Effect from "effect/Effect"
import type * as Redacted from "effect/Redacted"

import * as Context from "effect/Context"

import type * as Auth from "./Auth.js"
import type * as CurrentUser from "./CurrentUser.js"

/**
 * @since 0.0.0
 * @category models
 */
export interface TokenVerifierService {
  readonly verify: (credential: Redacted.Redacted) => Effect.Effect<CurrentUser.AuthPrincipal, Auth.Unauthorized>
}

/**
 * @since 0.0.0
 * @category services
 */
export class TokenVerifier extends Context.Service<TokenVerifier, TokenVerifierService>()(
  "@replaceme/domain/TokenVerifier",
) {}
