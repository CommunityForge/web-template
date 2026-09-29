/**
 * Supabase's JWT claim layout, decoded into the domain principal.
 *
 * ## What this module is, and is not
 *
 * It is a faithful decoder of Supabase's _published_ access-token contract — which claims exist, which are guaranteed
 * present, and which of them a server may trust. That is a fact about Supabase, so it belongs here.
 *
 * It is deliberately not a policy. Whether an anonymous user may call a route, or which subscription tier unlocks what,
 * is the consuming domain's business; this module's job is to hand that decision typed inputs. Hence {@link make}: the
 * envelope is fixed, and the caller supplies the schema for the one claim whose contents are application-specific.
 *
 * ## Why `role` is asserted but anonymity is not
 *
 * Supabase issues `role: "authenticated"` to _every_ signed-in user, anonymous or permanent — `is_anonymous` is the
 * only thing that separates them. So asserting the role excludes a genuinely different class of credential (the
 * publishable anon key, and any `service_role` token) without silently admitting or rejecting anonymous users. Gating
 * on anonymity is a route-level decision, made against the surfaced flag.
 *
 * ## Why `user_metadata` is absent
 *
 * `raw_user_meta_data` is user-editable and therefore unusable for authorization. Modeling it would put it one
 * autocomplete away from a policy check, so it is not modeled at all. Authorization data belongs in `app_metadata`,
 * which only the server can write.
 *
 * @since 0.0.0
 */

import * as Auth from "@landbank/domain/Auth"
import * as CurrentUser from "@landbank/domain/CurrentUser"
import * as User from "@landbank/domain/User"
import * as Effect from "effect/Effect"
import { pipe } from "effect/Function"
import * as Option from "effect/Option"
import * as Schema from "effect/Schema"
import * as SchemaParser from "effect/SchemaParser"

/**
 * What an `app_metadata` schema may be: anything, so long as decoding it needs no services.
 *
 * The token verifier runs inside a request with nothing provided, so a schema whose decoding required an Effect service
 * would have no way to discharge it. Pinning that here turns it into a compile error at the composition root rather
 * than an unsatisfiable requirement at the call site.
 *
 * @since 0.0.0
 * @category models
 */
export type AppMetadataSchema = Schema.Top & { readonly DecodingServices: never }

/**
 * The claims Supabase guarantees on an access token, plus the one it does not.
 *
 * Per Supabase's JWT claims reference, `iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`, `email`, `phone`
 * and `is_anonymous` are always present; `app_metadata`, `user_metadata`, `amr`, `jti` and `nbf` are optional. Only the
 * ones a server has a reason to read are modeled — `exp`, `iat` and `iss` are verified by the JWKS layer before this
 * ever runs, so restating them here would be a second, weaker check rather than a stronger one.
 *
 * @since 0.0.0
 * @category schemas
 */
export const make = <S extends AppMetadataSchema>(appMetadata: S) =>
  Schema.Struct({
    /**
     * the user id
     */
    sub: User.UserId,

    /**
     * Present on every Supabase token; the JWKS layer is what checks its _value_. Modeled so a token missing it fails
     * here rather than reaching a principal.
     */
    aud: Schema.String,

    /**
     * `"authenticated"` covers both permanent and anonymous users. Anything else is not a user token.
     */
    role: Schema.Literals(["authenticated"]),

    /**
     * The permanent/anonymous discriminator. Required by Supabase, so it is required here — a token without it is not
     * one we know how to reason about.
     */
    is_anonymous: Schema.Boolean,

    email: Schema.optional(Schema.NullOr(Schema.String)),

    /**
     * Server-controlled. The only claim safe to base authorization on, and the reason this schema is a function.
     */
    app_metadata: Schema.optional(appMetadata),
  })

/**
 * Decode verified JWT claims into the domain principal. Plug this into the JWKS verifier at the server's composition
 * root, supplying the schema for whatever the application stores in `app_metadata`:
 *
 * ```ts
 * JwksTokenVerifier.layer({ ..., decode: SupabaseClaims.toPrincipal(Schema.Struct({})) })
 * ```
 *
 * Failures discard their cause: an `Unauthorized` that carried the issue tree would echo claim material back to the
 * caller.
 *
 * @since 0.0.0
 * @category decoding
 */
export const toPrincipal = <S extends AppMetadataSchema>(
  appMetadata: S,
): ((
  claims: unknown,
) => Effect.Effect<CurrentUser.AuthPrincipal<Exclude<S["Type"], undefined>>, Auth.Unauthorized>) => {
  // Built once per composition rather than per call: this runs on every authenticated request.
  const decode = SchemaParser.decodeUnknownEffect(make(appMetadata))

  return (claims) =>
    decode(claims).pipe(
      Effect.mapBoth({
        onSuccess: (decoded) => {
          const metadata = Option.fromUndefinedOr(decoded.app_metadata)
          // `is_anonymous` decides the arm: it is the issuer's own assertion, and the address is a weaker signal that
          // an emailless provider would leave absent on a genuine account.
          //
          // A guest arrives carrying `email: ""`, so a blank address is an ABSENT one. Lifting only `null` and
          // `undefined` would hand the member arm a present-but-empty address, which no consumer can use and which
          // the browser-side carrier reads as no address at all.
          const email = pipe(
            Option.fromNullishOr(decoded.email),
            Option.map((address) => address.trim()),
            Option.filter((address) => address.length > 0),
          )
          return decoded.is_anonymous
            ? CurrentUser.AuthPrincipal.Anonymous({ userId: decoded.sub, appMetadata: metadata })
            : CurrentUser.AuthPrincipal.Member({ userId: decoded.sub, email, appMetadata: metadata })
        },
        onFailure: () => new Auth.Unauthorized(),
      }),
    )
}
