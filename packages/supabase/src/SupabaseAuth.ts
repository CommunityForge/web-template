/**
 * Supabase concrete implementation of the `Auth` service.
 *
 * @since 0.0.0
 */

import type * as SupabaseJs from "@supabase/supabase-js"

import * as Auth from "@landbank/domain/Auth"
import * as Effect from "effect/Effect"
import { pipe } from "effect/Function"
import * as Layer from "effect/Layer"
import * as Match from "effect/Match"
import * as Option from "effect/Option"
import * as Redacted from "effect/Redacted"
import * as SubscriptionRef from "effect/SubscriptionRef"

import * as internalSession from "./internal/session.js"
import * as SupabaseClient from "./SupabaseClient.js"

/**
 * supabase-js _resolves_ rather than rejects when authentication fails, reporting the failure in the result's `error`
 * field. A wrapper that only guards the promise therefore reports every rejected password as a success — which is what
 * this lifts away. The nullable field becomes an `Option`, and a present error becomes a typed failure.
 */
const failWhenPresent = <E>(
  error: SupabaseJs.AuthError | null,
  onError: (error: SupabaseJs.AuthError) => E,
): Effect.Effect<void, E> =>
  Option.match(Option.fromNullishOr(error), {
    onNone: () => Effect.void,
    onSome: (present) => Effect.fail(onError(present)),
  })

/**
 * `AuthError.code` is a documented enum (`ErrorCode`, re-exported from `@supabase/auth-js`), so these mappers are exact
 * rather than a match on message text — the messages are server-side prose and change without notice. Anything outside
 * an operation's vocabulary falls through to `AuthError`.
 *
 * The two rate-limit codes are spelled out per operation rather than factored into a shared prefix, because each
 * mapper's return type is the statement of that operation's vocabulary and a shared prefix would erase it.
 */
const signInFailure = (
  error: SupabaseJs.AuthError,
): Auth.InvalidCredentials | Auth.EmailNotConfirmed | Auth.RateLimited | Auth.AuthError =>
  Match.value(error.code).pipe(
    Match.withReturnType<Auth.InvalidCredentials | Auth.EmailNotConfirmed | Auth.RateLimited | Auth.AuthError>(),
    Match.when("invalid_credentials", () => new Auth.InvalidCredentials()),
    Match.when("email_not_confirmed", () => new Auth.EmailNotConfirmed()),
    Match.whenOr("over_request_rate_limit", "over_email_send_rate_limit", () => new Auth.RateLimited()),
    Match.orElse(() => new Auth.AuthError({ message: "sign-in failed", cause: error })),
  )

/**
 * THE ENUMERATION COLLAPSE. `user_already_exists` and `email_exists` — GoTrue's two ways of saying "that address is
 * taken" — map to `EmailNotConfirmed`, the SAME value a brand-new address produces once confirmations are on, so the
 * caller has nothing to branch on even if it wanted to.
 *
 * Residual, stated rather than hidden: with `enable_confirmations = false` the two remain distinguishable no matter
 * what this function does, so the collapse holds only on a project that has confirmations on.
 */
const signUpFailure = (
  error: SupabaseJs.AuthError,
): Auth.EmailNotConfirmed | Auth.SignUpRejected | Auth.RateLimited | Auth.AuthError =>
  Match.value(error.code).pipe(
    Match.withReturnType<Auth.EmailNotConfirmed | Auth.SignUpRejected | Auth.RateLimited | Auth.AuthError>(),
    Match.whenOr("email_not_confirmed", "user_already_exists", "email_exists", () => new Auth.EmailNotConfirmed()),
    Match.when("weak_password", () => new Auth.SignUpRejected({ reason: "WeakPassword" })),
    Match.whenOr(
      "signup_disabled",
      "email_provider_disabled",
      () => new Auth.SignUpRejected({ reason: "SignupsDisabled" }),
    ),
    Match.whenOr("over_request_rate_limit", "over_email_send_rate_limit", () => new Auth.RateLimited()),
    Match.orElse(() => new Auth.AuthError({ message: "sign-up failed", cause: error })),
  )

/**
 * Asking for an email again — a confirmation resend, or a reset link. The vocabulary is the throttle and nothing else:
 * a refusal to send a SECOND copy rather than a failure to send the first, which the copy has to carry because the
 * person is looking at an inbox with nothing in it.
 *
 * A provider code reporting whether the address is known has no tag of its own to land on, and the `AuthError` it falls
 * through to takes a `message` fixed at the call site. `cause` still carries the raw error, so the collapse is in the
 * tags rather than in the whole value.
 */
const emailSendFailure =
  (message: string) =>
  (error: SupabaseJs.AuthError): Auth.RateLimited | Auth.AuthError =>
    Match.value(error.code).pipe(
      Match.withReturnType<Auth.RateLimited | Auth.AuthError>(),
      Match.whenOr("over_request_rate_limit", "over_email_send_rate_limit", () => new Auth.RateLimited()),
      Match.orElse(() => new Auth.AuthError({ message, cause: error })),
    )

/**
 * Completing a reset.
 *
 * `weak_password` reuses `SignUpRejected.WeakPassword` rather than minting a second tag, so the sign-up form and the
 * reset form cannot drift into refusing the same password for differently-worded reasons. The three link codes all mean
 * the recovery session lapsed while the person typed, and all mean "ask for another one".
 *
 * `same_password` and the `reauthentication_*` codes are deliberately unmapped: changing a password from inside a live
 * session is not built, and inventing copy for an unreachable path is how dead copy is born.
 */
const setNewPasswordFailure = (
  error: SupabaseJs.AuthError,
): Auth.SignUpRejected | Auth.LinkInvalid | Auth.RateLimited | Auth.AuthError =>
  Match.value(error.code).pipe(
    Match.withReturnType<Auth.SignUpRejected | Auth.LinkInvalid | Auth.RateLimited | Auth.AuthError>(),
    Match.when("weak_password", () => new Auth.SignUpRejected({ reason: "WeakPassword" })),
    Match.whenOr("otp_expired", "flow_state_expired", "flow_state_not_found", () => new Auth.LinkInvalid()),
    Match.whenOr("over_request_rate_limit", "over_email_send_rate_limit", () => new Auth.RateLimited()),
    Match.orElse(() => new Auth.AuthError({ message: "could not set the new password", cause: error })),
  )

/**
 * Where an emailed link lands, and which round trip it was. One path derived from the one configured origin, rather
 * than three independently-set values that are three ways to be missing from the redirect allow-list.
 *
 * THE `flow` MARKER is deliberately OURS rather than the SDK's: under `flowType: "pkce"` the exchange emits `SIGNED_IN`
 * for BOTH round trips, so supabase-js's `PASSWORD_RECOVERY` event would drop someone who followed a reset link
 * straight into the app without ever asking for a new password. It carries no authority — it selects a screen, and the
 * session decides what that screen may do.
 *
 * Note for the allow-list: entries match the URL including its query, so the configured origin needs a pattern that
 * admits `/auth/callback?flow=*` rather than the bare path.
 */
const callbackUrl = (redirectTo: URL, flow: "confirm" | "recovery"): string => {
  // `new URL(path, base)` takes the origin and discards any path the base carried, which is what makes this safe to
  // derive from a value whose job is to name an origin. The marker goes on through `searchParams` so it is escaped
  // rather than interpolated.
  const url = new URL("/auth/callback", redirectTo)
  url.searchParams.set("flow", flow)
  return url.toString()
}

/**
 * @since 0.0.0
 * @category layers
 */
export const layer: Layer.Layer<Auth.Auth, never, SupabaseClient.SupabaseClient> = Layer.effect(
  Auth.Auth,
  Effect.gen(function* () {
    const { client, redirectTo } = yield* SupabaseClient.SupabaseClient

    const ref = yield* SubscriptionRef.make(Option.none<Auth.Session>())

    /**
     * Seed from persisted storage before subscribing; a failure here is "not signed in", not a failure to construct the
     * service.
     *
     * That sentence used to be FALSE, and the gap cost the whole app: `fromSupabase` was built from the THROWING schema
     * constructors, so a session that would not decode raised a DEFECT -- and `Effect.ignore` discharges only the typed
     * error channel. The defect escaped, `Layer.effect` propagated it, and the app's one `Layer.orDie` turned it into a
     * store that never launched. An anonymous user's `email: ""` was enough.
     *
     * The FIX is in `./internal/session.ts`, which is now total by construction (`makeOption` / `DateTime.make`), so
     * there is no defect to escape and `Effect.ignore` is once again an honest statement of intent.
     *
     * `Effect.catchDefect` stays as containment, not as the fix, and it earns its place for a specific reason: this
     * seed runs during LAYER CONSTRUCTION, where the blast radius of one bad decode is the whole application rather
     * than one signed-out user. A schema drifting out from under this adapter should degrade to "not signed in" with a
     * logged reason -- silence is what made the original failure so expensive to find -- not repeat the outage.
     */
    yield* Effect.tryPromise({
      try: () => client.auth.getSession(),
      catch: () => undefined,
    }).pipe(
      Effect.flatMap(({ data }) => SubscriptionRef.set(ref, internalSession.fromSupabase(data.session))),
      Effect.catchDefect((defect) =>
        Effect.logWarning("SupabaseAuth: stored session could not be decoded -- treating as signed out", defect),
      ),
      Effect.ignore,
    )

    /**
     * supabase-js warns against awaiting SDK calls inside this callback (it deadlocks the navigator lock); a
     * synchronous ref update is safe.
     *
     * `runSyncExit` rather than `runSync`, and the reason is specific to WHOSE stack this callback runs on. supabase-js
     * invokes it while holding the `navigator.locks` acquisition that every other auth call queues behind, so a throw
     * escaping here does not merely lose a ref update -- it unwinds through SDK code that has no idea what an Effect
     * defect is, on the one code path that can wedge the auth client for the rest of the page's life. `runSync`
     * rethrows into that; `runSyncExit` keeps the outcome a value, so the worst case is a ref that does not advance.
     */
    const { data: subscription } = client.auth.onAuthStateChange((_event, session) => {
      Effect.runSyncExit(
        // `Effect.suspend`, and it is load-bearing rather than ceremony: `fromSupabase` is an ordinary eager call, so
        // spelled as a bare argument to `SubscriptionRef.set` it runs while BUILDING the effect -- outside the runtime,
        // where nothing below can see a throw. Suspending moves it inside, which is what makes `runSyncExit`'s
        // containment cover the decode and not just the ref write.
        Effect.suspend(() => SubscriptionRef.set(ref, internalSession.fromSupabase(session))).pipe(
          Effect.catchDefect((defect) =>
            Effect.logWarning("SupabaseAuth: auth-state session could not be decoded -- ignoring", defect),
          ),
        ),
      )
    })

    yield* Effect.addFinalizer(() => Effect.sync(() => subscription.subscription.unsubscribe()))

    const accessToken: Effect.Effect<Redacted.Redacted, Auth.Unauthorized> = Effect.tryPromise({
      try: () => client.auth.getSession(),
      catch: () => new Auth.Unauthorized(),
    }).pipe(
      Effect.flatMap(({ data }) =>
        Option.match(Option.fromNullishOr(data.session), {
          onNone: () => Effect.fail(new Auth.Unauthorized()),
          onSome: (session) => Effect.succeed(Redacted.make(session.access_token)),
        }),
      ),
    )

    const signInWithOAuth = (provider: Auth.OAuthProvider): Effect.Effect<void, Auth.AuthError> =>
      Effect.tryPromise({
        try: () =>
          client.auth.signInWithOAuth({
            provider,
            options: { redirectTo: redirectTo.toString() },
          }),
        catch: (cause) => new Auth.AuthError({ message: "OAuth sign-in failed", cause }),
      }).pipe(
        Effect.flatMap(({ error }) =>
          failWhenPresent(error, (cause) => new Auth.AuthError({ message: "OAuth sign-in failed", cause })),
        ),
      )

    const signUpWithPassword = Effect.fn("SupabaseAuth.signUpWithPassword")((credentials: Auth.PasswordCredentials) =>
      pipe(
        Effect.tryPromise({
          try: () =>
            client.auth.signUp({
              email: credentials.email,
              password: Redacted.value(credentials.password),
              // Without this the confirmation link falls back to the project's `site_url` and lands the person on the
              // app root carrying an unconsumed token, where nothing is listening for it.
              options: { emailRedirectTo: callbackUrl(redirectTo, "confirm") },
            }),
          catch: (cause) => new Auth.AuthError({ message: "sign-up failed", cause }),
        }),
        Effect.flatMap(({ data, error }) =>
          pipe(
            failWhenPresent(error, signUpFailure),
            /**
             * With confirmations enabled a successful sign-up carries no error and no session: the account exists but
             * cannot be used yet, which is `EmailNotConfirmed` to the domain. `signUpFailure` above lands the
             * ERROR-shaped form of the taken-address case on this same tag, so both arrive at one value from both
             * directions — the property the surfacing rule asks for.
             */
            Effect.flatMap(() =>
              Option.match(Option.fromNullishOr(data.session), {
                onNone: () => Effect.fail(new Auth.EmailNotConfirmed()),
                onSome: () => Effect.void,
              }),
            ),
          ),
        ),
      ),
    )

    const signInWithPassword = Effect.fn("SupabaseAuth.signInWithPassword")((credentials: Auth.PasswordCredentials) =>
      pipe(
        Effect.tryPromise({
          try: () =>
            client.auth.signInWithPassword({
              email: credentials.email,
              password: Redacted.value(credentials.password),
            }),
          catch: (cause) => new Auth.AuthError({ message: "sign-in failed", cause }),
        }),
        Effect.flatMap(({ error }) => failWhenPresent(error, signInFailure)),
      ),
    )

    /**
     * `type: "signup"` and not `"email_change"`: this resends the CONFIRMATION for an address that never completed its
     * round trip, which is the only resend this product has.
     *
     * `emailRedirectTo` has to be passed AGAIN — the resent link is minted fresh and carries whatever this call says,
     * so omitting it falls back to the project's `site_url`.
     */
    const resendConfirmation = Effect.fn("SupabaseAuth.resendConfirmation")((request: Auth.EmailRequest) =>
      pipe(
        Effect.tryPromise({
          try: () =>
            client.auth.resend({
              type: "signup",
              email: request.email,
              options: { emailRedirectTo: callbackUrl(redirectTo, "confirm") },
            }),
          catch: (cause) => new Auth.AuthError({ message: "could not resend the confirmation email", cause }),
        }),
        Effect.flatMap(({ error }) =>
          failWhenPresent(error, emailSendFailure("could not resend the confirmation email")),
        ),
      ),
    )

    /**
     * Non-disclosing by the provider's own construction: `recover` answers `200` for an address that has never signed
     * up, so there is no case here to mask and no branch to get wrong.
     */
    const requestPasswordReset = Effect.fn("SupabaseAuth.requestPasswordReset")((request: Auth.EmailRequest) =>
      pipe(
        Effect.tryPromise({
          try: () =>
            client.auth.resetPasswordForEmail(request.email, { redirectTo: callbackUrl(redirectTo, "recovery") }),
          catch: (cause) => new Auth.AuthError({ message: "could not send the reset email", cause }),
        }),
        Effect.flatMap(({ error }) => failWhenPresent(error, emailSendFailure("could not send the reset email"))),
      ),
    )

    /**
     * Acts on whoever the recovery link signed in, which is why it takes no address: supabase-js consumed the link's
     * tokens on the landing route and the session it produced is the only thing selecting the account. Passing an
     * address here would not select a different one; it would change THIS account's address.
     */
    const setNewPassword = Effect.fn("SupabaseAuth.setNewPassword")((request: Auth.NewPassword) =>
      pipe(
        Effect.tryPromise({
          try: () => client.auth.updateUser({ password: Redacted.value(request.password) }),
          catch: (cause) => new Auth.AuthError({ message: "could not set the new password", cause }),
        }),
        Effect.flatMap(({ error }) => failWhenPresent(error, setNewPasswordFailure)),
      ),
    )

    /**
     * A failed anonymous sign-in has no finer vocabulary than `AuthError`: there is no credential to be wrong. The
     * notable code that lands here is `anonymous_provider_disabled` (the feature toggled off server-side), which the
     * caller can do nothing about — so it stays generic, with the cause preserved for diagnostics.
     */
    const signInAnonymously: Effect.Effect<void, Auth.AuthError> = Effect.tryPromise({
      try: () => client.auth.signInAnonymously(),
      catch: (cause) => new Auth.AuthError({ message: "anonymous sign-in failed", cause }),
    }).pipe(
      Effect.flatMap(({ error }) =>
        failWhenPresent(error, (cause) => new Auth.AuthError({ message: "anonymous sign-in failed", cause })),
      ),
    )

    /**
     * `scope: "local"` because the default is `"global"`, which revokes every session the user has on every device.
     * Signing out of one tab is not a request to be signed out everywhere.
     */
    const signOut: Effect.Effect<void, Auth.AuthError> = Effect.tryPromise({
      try: () => client.auth.signOut({ scope: "local" }),
      catch: (cause) => new Auth.AuthError({ message: "sign-out failed", cause }),
    }).pipe(
      Effect.flatMap(({ error }) =>
        failWhenPresent(error, (cause) => new Auth.AuthError({ message: "sign-out failed", cause })),
      ),
    )

    return Auth.Auth.of({
      session: SubscriptionRef.get(ref),
      changes: SubscriptionRef.changes(ref),
      accessToken,
      signInWithOAuth,
      signInWithPassword,
      signUpWithPassword,
      resendConfirmation,
      requestPasswordReset,
      setNewPassword,
      signInAnonymously,
      signOut,
    })
  }),
)
