/**
 * The client-side authentication alphabet.
 *
 * THE SURFACING RULE: no operation here may return a failure that distinguishes a registered address from an
 * unregistered one -- not a distinct tag, not a distinct `AuthError.message`, not a present-versus-absent failure. It
 * is a property of the ERROR CHANNEL before it is a property of any screen, because a scripted attacker reads the
 * response rather than the page. The types below cannot enforce it — `AuthError` carries a free-form `message` and an
 * opaque `cause`, which are two places a provider's taken-address code would fit — so the rule binds whoever maps those
 * codes onto these tags. Where it IS visible in the types is a member deliberately missing from
 * {@link SignUpRejected}.
 *
 * Deliberately NOT claimed: timing. Two cases that differ only in response latency remain distinguishable.
 *
 * @since 0.0.0
 */

import type * as Effect from "effect/Effect"
import type * as Option from "effect/Option"
import type * as Redacted from "effect/Redacted"
import type * as Stream from "effect/Stream"

import * as Context from "effect/Context"
import * as Schema from "effect/Schema"

import * as User from "./User.js"

/**
 * @since 0.0.0
 * @category models
 */
export const OAuthProvider = Schema.Literals(["google", "github"])

/**
 * @since 0.0.0
 * @category models
 */
export type OAuthProvider = typeof OAuthProvider.Type

/**
 * An address as this domain will accept one: trimmed, and non-empty once trimmed.
 *
 * @since 0.0.0
 * @category models
 */
export const EmailAddress = Schema.Trimmed.pipe(Schema.check(Schema.isNonEmpty()))

/**
 * @since 0.0.0
 * @category models
 */
export type EmailAddress = typeof EmailAddress.Type

/**
 * {@link EmailAddress} from raw form input, trimming rather than rejecting.
 *
 * @since 0.0.0
 * @category models
 */
export const EmailAddressFromInput = Schema.Trim.pipe(Schema.check(Schema.isNonEmpty()))

/**
 * The total parse a UI needs. `EmailAddress` is a CHECK, so constructing an action payload from an untrimmed string
 * throws; screens gate on this instead of re-spelling the check.
 *
 * @since 0.0.0
 * @category constructors
 */
export const parseEmailAddress: (input: string) => Option.Option<EmailAddress> =
  Schema.decodeUnknownOption(EmailAddressFromInput)

export const PasswordCredentials = Schema.Struct({
  email: EmailAddress,
  password: User.Password,
})
export type PasswordCredentials = typeof PasswordCredentials.Type

/**
 * An address on its own. A struct rather than a bare parameter so the client slice can carry it as an action's fields,
 * naming the field once in the domain.
 *
 * @since 0.0.0
 * @category models
 */
export const EmailRequest = Schema.Struct({ email: EmailAddress })

/**
 * @since 0.0.0
 * @category models
 */
export type EmailRequest = typeof EmailRequest.Type

/**
 * A replacement password, for the reset-completion path.
 *
 * The address is absent ON PURPOSE: completing a reset acts on whoever the recovery link signed in, so accepting an
 * address here would invite a caller to believe it selects the account. It does not.
 *
 * @since 0.0.0
 * @category models
 */
export const NewPassword = Schema.Struct({ password: User.Password })

/**
 * @since 0.0.0
 * @category models
 */
export type NewPassword = typeof NewPassword.Type

export class InvalidCredentials extends Schema.TaggedError<InvalidCredentials>("@replaceme/domain/InvalidCredentials")(
  "InvalidCredentials",
  {},
) {}

export class EmailNotConfirmed extends Schema.TaggedError<EmailNotConfirmed>("@replaceme/domain/EmailNotConfirmed")(
  "EmailNotConfirmed",
  {},
) {}

/**
 * Sign-up refused for a reason the caller can act on.
 *
 * `EmailInUse` is NOT a member, and its absence is load-bearing: it was the shipped enumeration oracle this module's
 * header forbids.
 *
 * @since 0.0.0
 * @category errors
 */
export class SignUpRejected extends Schema.TaggedError<SignUpRejected>("@replaceme/domain/SignUpRejected")(
  "SignUpRejected",
  {
    reason: Schema.Literals(["WeakPassword", "SignupsDisabled"]),
  },
) {}

/**
 * The caller has made too many attempts and is being throttled.
 *
 * Distinct from {@link InvalidCredentials} because the remedy is -- waiting, rather than typing something different. No
 * retry-after: GoTrue puts the remaining interval in prose rather than a structured field, and mapping on message text
 * is what this domain's failures are built to avoid, so a caller that wants a countdown owns the clock itself.
 *
 * @since 0.0.0
 * @category errors
 */
export class RateLimited extends Schema.TaggedError<RateLimited>("@replaceme/domain/RateLimited")("RateLimited", {}) {}

/**
 * An emailed link -- confirmation or recovery -- has expired, or has already been used.
 *
 * One tag for both round trips, because the remedy is the same: ask for another. Distinguishing them would tell the
 * holder of a link which kind it was, which is information they already have.
 *
 * @since 0.0.0
 * @category errors
 */
export class LinkInvalid extends Schema.TaggedError<LinkInvalid>("@replaceme/domain/LinkInvalid")("LinkInvalid", {}) {}

/**
 * A client-side session: the authenticated user and the credential's expiry.
 *
 * Tokens are deliberately absent. Token acquisition is an effect on the `Auth` service (`accessToken`), because the
 * adapter may need to refresh before answering. A stored token field invites staleness bugs. Refresh tokens never leave
 * the adapter.
 *
 * @since 0.0.0
 * @category models
 */
export class Session extends Schema.Class<Session>("@replaceme/domain/Session")({
  user: User.User,
  expiresAt: Schema.DateTimeUtc,
}) {}

/**
 * Failure of an authentication operation.
 *
 * @since 0.0.0
 * @category errors
 */
export class AuthError extends Schema.TaggedError<AuthError>("@replaceme/domain/AuthError")("AuthError", {
  message: Schema.String,
  cause: Schema.optional(Schema.Unknown),
}) {}

/**
 * The request carried no valid credential.
 *
 * @since 0.0.0
 * @category errors
 */
export class Unauthorized extends Schema.TaggedError<Unauthorized>("@replaceme/domain/Unauthorized")(
  "Unauthorized",
  {},
  { httpApiStatus: 401 },
) {}

/**
 * The client-side authentication capability.
 *
 * @since 0.0.0
 * @category models
 */
export interface AuthService {
  /**
   * The current session, if any.
   */
  readonly session: Effect.Effect<Option.Option<Session>>

  /**
   * Emits on every session change after subscription (sign-in, sign-out, refresh-driven user changes). Read `session`
   * for the current value.
   */
  readonly changes: Stream.Stream<Option.Option<Session>>

  /**
   * A currently-valid access token; the adapter refreshes if needed. This is the single integration point used by the
   * HttpApi client middleware.
   */
  readonly accessToken: Effect.Effect<Redacted.Redacted, Unauthorized>

  /**
   * Begin an OAuth sign-in. In browsers, this typically navigates away; the adapter completes the flow on return and
   * `changes` emits the new session.
   */
  readonly signInWithOAuth: (provider: OAuthProvider) => Effect.Effect<void, AuthError>

  /**
   * Turn an address and password into an account.
   *
   * This CREATES an identity; it never promotes the live one. Calling it during a guest session mints a NEW user id and
   * leaves everything the guest owns with the guest identity in that browser. This port carries no promotion operation,
   * and one added here would owe the surfacing rule on its own terms rather than inherit it from this signature.
   *
   * `EmailNotConfirmed` is the ordinary SUCCESS shape once confirmations are on, and carries no information about
   * whether the address was already registered.
   */
  readonly signUpWithPassword: (
    credentials: PasswordCredentials,
  ) => Effect.Effect<void, EmailNotConfirmed | SignUpRejected | RateLimited | AuthError>

  readonly signInWithPassword: (
    credentials: PasswordCredentials,
  ) => Effect.Effect<void, InvalidCredentials | EmailNotConfirmed | RateLimited | AuthError>

  /**
   * Send the confirmation email again for an address that has signed up but not yet completed the round trip.
   *
   * `RateLimited` when the provider's enforced interval has not elapsed -- which is a refusal to send a SECOND copy,
   * not a failure to send the first.
   */
  readonly resendConfirmation: (request: EmailRequest) => Effect.Effect<void, RateLimited | AuthError>

  /**
   * Ask for a password-reset link.
   *
   * Reports success for an address that has never signed up, exactly as it does for one that has. That is the surfacing
   * rule, and here it costs nothing to honor: the provider's recover endpoint is already non-disclosing.
   */
  readonly requestPasswordReset: (request: EmailRequest) => Effect.Effect<void, RateLimited | AuthError>

  /**
   * Replace the password of whoever the recovery link signed in.
   *
   * `SignUpRejected` with reason `WeakPassword` rather than a tag of its own, so one weak-password refusal serves both
   * the sign-up form and the reset form and they cannot drift into saying different things.
   */
  readonly setNewPassword: (
    request: NewPassword,
  ) => Effect.Effect<void, SignUpRejected | LinkInvalid | RateLimited | AuthError>

  /**
   * Mint an anonymous session. The identity is real — an anonymous user owns rows like any other — and linking it to an
   * email later preserves the user id, so nothing owned is orphaned by signing up. Idempotence is the CALLER'S concern:
   * invoking this with a live session would replace it, so guard on `session` first (the ensure-session layer does).
   */
  readonly signInAnonymously: Effect.Effect<void, AuthError>

  /**
   * Terminate the current session. `changes` emits `Option.none()`.
   */
  readonly signOut: Effect.Effect<void, AuthError>
}

/**
 * @since 0.0.0
 * @category services
 */
export class Auth extends Context.Service<Auth, AuthService>()("@replaceme/domain/Auth") {}
