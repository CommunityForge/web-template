/**
 * The server-side, request-scoped principal.
 *
 * @since 0.0.0
 */

import type * as Option from "effect/Option"

import * as Context from "effect/Context"
import * as Data from "effect/Data"

import type * as User from "./User.js"

/**
 * The verified principal, as the two identities it can be: a guest, or an account holder.
 *
 * Both carry the same `authenticated` role, so the role cannot be asked and something else has to separate them — a
 * route meaning "signed-in humans only" must say so against this type. The separator is the TAG, so anonymity is
 * carried once and cannot disagree with itself.
 *
 * Only the member arm has an address to hold. It stays optional there because the address is a weaker signal than the
 * tag: a provider that authenticates without one yields an account holder with nothing to put in the field, and the arm
 * must be able to say so without pretending to be a guest.
 *
 * @since 0.0.0
 * @category models
 */
export type AuthPrincipal<AppMetadata = unknown> = Data.TaggedEnum<{
  Anonymous: {
    readonly userId: User.UserId

    /**
     * Server-controlled claims, shaped by whatever schema the composition root handed the token decoder.
     *
     * This is where entitlements belong — never `user_metadata`, which the user can edit at will. `unknown` by default
     * because nothing in the domain writes it yet; narrow the parameter at the point a feature needs it.
     */
    readonly appMetadata: Option.Option<AppMetadata>
  }
  Member: {
    readonly userId: User.UserId

    /**
     * Only what verified credentials reliably carry. An address present but blank is lifted to `None` at the decode
     * boundary, so `Some` always holds something usable.
     */
    readonly email: Option.Option<string>

    /**
     * See {@link AuthPrincipal}'s `Anonymous` arm.
     */
    readonly appMetadata: Option.Option<AppMetadata>
  }
}>

/**
 * The `WithGenerics` lambda for {@link AuthPrincipal}, so the constructors infer `AppMetadata` at generic call sites
 * without a cast — `SupabaseClaims.toPrincipal` builds the principal under the schema its caller supplied.
 *
 * @since 0.0.0
 * @category models
 */
export interface AuthPrincipalLambda extends Data.TaggedEnum.WithGenerics<1> {
  readonly taggedEnum: AuthPrincipal<this["A"]>
}

/**
 * Constructors and matchers for {@link AuthPrincipal}.
 *
 * @since 0.0.0
 * @category constructors
 */
export const AuthPrincipal = Data.taggedEnum<AuthPrincipalLambda>()

/**
 * Whether this principal is a guest rather than an account holder — the tag, under the name every call site already
 * used. Derived, so it cannot disagree with the identity it describes.
 *
 * @since 0.0.0
 * @category predicates
 */
export const isAnonymous = <AppMetadata>(principal: AuthPrincipal<AppMetadata>): boolean =>
  AuthPrincipal.$is("Anonymous")(principal)

/**
 * @since 0.0.0
 * @category services
 */
export class CurrentUser extends Context.Service<CurrentUser, AuthPrincipal>()("@replaceme/domain/CurrentUser") {}
