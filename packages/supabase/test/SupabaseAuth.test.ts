/**
 * The pin on "a failed sign-in must not look like a successful one".
 *
 * `signInWithPassword` and `signUpWithPassword` previously ended in `Effect.asVoid`, discarding the `error` field that
 * supabase-js reports failures in. Every case below fails against that version and passes against the current one, so
 * this file is the regression boundary rather than a description of the happy path.
 */
/* Test-only assertions. Two shapes, neither reachable by a constructor:
 *   - narrowing a value a RUNTIME check in the same test already established -- `map.get(k)` after `map.has(k)`, or a
 *     failure's concrete type after its tag was asserted -- where the refinement is the assertion above it; and
 *   - test doubles deliberately typed `never`/loosely, whose whole purpose is to stand somewhere the real type cannot.
 * A failed assumption here fails the test it is written in, which is the check a `.make` would otherwise provide. */
/* eslint-disable typescript/no-unsafe-type-assertion */

import type * as User from "@landbank/domain/User"

import { assert, describe, it } from "@effect/vitest"
import * as Auth from "@landbank/domain/Auth"
import * as SupabaseAuth from "@landbank/supabase/SupabaseAuth"
import * as Effect from "effect/Effect"
import * as Layer from "effect/Layer"
import * as Redacted from "effect/Redacted"
import * as Result from "effect/Result"

import * as ScriptedAuthClient from "./ScriptedAuthClient.js"

const credentials: Auth.PasswordCredentials = {
  email: "member@example.com",
  password: Redacted.make("correct horse battery staple") as User.Password,
}

/**
 * Local combinator rather than `it.layer`, because each case scripts a different client.
 */
const provideAuth =
  (scripted: ReturnType<typeof ScriptedAuthClient.make>) =>
  <A, E, R>(self: Effect.Effect<A, E, R>) =>
    Effect.provide(self, SupabaseAuth.layer.pipe(Layer.provide(scripted.layer)))

/**
 * Runs one `Auth` operation against a scripted client and hands back the `Result` for inspection.
 */
const attempt = <A, E>(script: ScriptedAuthClient.Script, use: (auth: Auth.AuthService) => Effect.Effect<A, E>) =>
  Effect.gen(function* () {
    const auth = yield* Auth.Auth
    return yield* Effect.result(use(auth))
  }).pipe(provideAuth(ScriptedAuthClient.make(script)))

describe("SupabaseAuth", () => {
  describe("signInWithPassword", () => {
    it.effect("fails with InvalidCredentials when the server rejects the password", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("invalid_credentials") } },
          (auth) => auth.signInWithPassword(credentials),
        )

        assert.isTrue(
          Result.isFailure(result),
          "a rejected password reported success — the `error` field is being discarded again",
        )
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "InvalidCredentials")
        }
      }),
    )

    it.effect("fails with EmailNotConfirmed when the account exists but is unverified", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("email_not_confirmed") } },
          (auth) => auth.signInWithPassword(credentials),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "EmailNotConfirmed")
        }
      }),
    )

    /**
     * This case used to assert `AuthError` -- the fall-through the domain had no better tag for. A throttled person and
     * a person with the wrong password were told the same thing, so the one who only had to WAIT kept retrying a
     * password that was never wrong.
     */
    it.effect("maps a throttled request to RateLimited, not to the generic failure", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("over_request_rate_limit") } },
          (auth) => auth.signInWithPassword(credentials),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "RateLimited")
        }
      }),
    )

    it.effect("still falls back to AuthError for codes the domain has no tag for", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("user_banned") } },
          (auth) => auth.signInWithPassword(credentials),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "AuthError")
        }
      }),
    )

    /**
     * The distinctness this pins is a requirement, not a nicety: the two refusals must not be the same value, because
     * the copy is chosen by tag and identical tags mean identical advice.
     */
    it.effect("a wrong password and a throttled attempt are different failures", () =>
      Effect.gen(function* () {
        const wrong = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("invalid_credentials") } },
          (auth) => auth.signInWithPassword(credentials),
        )
        const throttled = yield* attempt(
          { signInWithPassword: { error: ScriptedAuthClient.authError("over_request_rate_limit") } },
          (auth) => auth.signInWithPassword(credentials),
        )

        assert.isTrue(Result.isFailure(wrong) && Result.isFailure(throttled))
        if (Result.isFailure(wrong) && Result.isFailure(throttled)) {
          assert.notStrictEqual(
            wrong.failure._tag,
            throttled.failure._tag,
            "a throttled attempt and a wrong password collapsed to one tag, so both get the same advice",
          )
        }
      }),
    )

    it.effect("succeeds when the server reports no error", () =>
      Effect.gen(function* () {
        const result = yield* attempt({ signInWithPassword: { error: null } }, (auth) =>
          auth.signInWithPassword(credentials),
        )

        assert.isTrue(Result.isSuccess(result), "a clean sign-in was reported as a failure")
      }),
    )
  })

  describe("signUpWithPassword", () => {
    /**
     * THE ENUMERATION PIN, and the most important case in this file.
     *
     * It used to assert the opposite -- that a duplicate address produced `SignUpRejected/EmailInUse`, which the login
     * screen rendered as "That address is already registered". That was an oracle anyone could query, one address at a
     * time, by POSTing a sign-up and reading the response.
     *
     * Both codes now have to land on the SAME value a fresh address produces. Asserting the tag alone would be too weak
     * -- `AuthError` would satisfy "not EmailInUse" while still separating the two cases -- so the assertion is
     * equality against the untaken outcome, which is the property the requirement actually states.
     */
    it.effect("a registered address is indistinguishable from an unregistered one", () =>
      Effect.gen(function* () {
        const fresh = yield* attempt({ signUp: { error: null, session: null } }, (auth) =>
          auth.signUpWithPassword(credentials),
        )

        const outcomes = yield* Effect.forEach(["user_already_exists", "email_exists"] as const, (code) =>
          attempt({ signUp: { error: ScriptedAuthClient.authError(code) } }, (auth) =>
            auth.signUpWithPassword(credentials),
          ),
        )

        assert.isTrue(Result.isFailure(fresh))
        if (Result.isFailure(fresh)) {
          assert.strictEqual(fresh.failure._tag, "EmailNotConfirmed")
          for (const taken of outcomes) {
            assert.isTrue(Result.isFailure(taken))
            if (Result.isFailure(taken)) {
              assert.deepStrictEqual(
                taken.failure,
                fresh.failure,
                "signing up with a taken address produced a different value than a fresh one — the oracle is back",
              )
            }
          }
        }
      }),
    )

    it.effect("points the confirmation link at the landing route, marked as a confirmation", () =>
      Effect.gen(function* () {
        const scripted = ScriptedAuthClient.make({ signUp: { error: null, session: null } })

        yield* Effect.gen(function* () {
          const auth = yield* Auth.Auth
          return yield* Effect.result(auth.signUpWithPassword(credentials))
        }).pipe(provideAuth(scripted))

        assert.deepStrictEqual(
          scripted.calls.signUpRedirects,
          ["https://example.test/auth/callback?flow=confirm"],
          "without an explicit redirect the link falls back to site_url and lands where nothing is listening",
        )
      }),
    )

    it.effect("maps a weak password to SignUpRejected/WeakPassword", () =>
      Effect.gen(function* () {
        const result = yield* attempt({ signUp: { error: ScriptedAuthClient.authError("weak_password") } }, (auth) =>
          auth.signUpWithPassword(credentials),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual((result.failure as Auth.SignUpRejected).reason, "WeakPassword")
        }
      }),
    )

    it.effect("reports EmailNotConfirmed when sign-up succeeds without a session", () =>
      Effect.gen(function* () {
        // What Supabase returns with email confirmations enabled: the account exists, but cannot be used yet.
        const result = yield* attempt({ signUp: { error: null, session: null } }, (auth) =>
          auth.signUpWithPassword(credentials),
        )

        assert.isTrue(
          Result.isFailure(result),
          "a sign-up needing confirmation reported plain success, so the UI would say nothing",
        )
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "EmailNotConfirmed")
        }
      }),
    )
  })

  describe("resendConfirmation", () => {
    it.effect("reports RateLimited when the enforced wait has not elapsed", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { resend: { error: ScriptedAuthClient.authError("over_email_send_rate_limit") } },
          (auth) => auth.resendConfirmation({ email: credentials.email }),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(
            result.failure._tag,
            "RateLimited",
            "a refusal to send a SECOND copy read as a failure to send the first",
          )
        }
      }),
    )

    it.effect("re-states the landing route, because the resent link is minted fresh", () =>
      Effect.gen(function* () {
        const scripted = ScriptedAuthClient.make({ resend: { error: null } })

        yield* Effect.gen(function* () {
          const auth = yield* Auth.Auth
          return yield* Effect.result(auth.resendConfirmation({ email: credentials.email }))
        }).pipe(provideAuth(scripted))

        assert.deepStrictEqual(scripted.calls.resendRedirects, ["https://example.test/auth/callback?flow=confirm"])
      }),
    )
  })

  describe("requestPasswordReset", () => {
    /**
     * The provider's recover endpoint answers `200` for an address that has never signed up -- measured against the
     * local stack, not assumed -- so the adapter has nothing to mask and this is the whole of the behavior.
     */
    it.effect("succeeds for an address with no account, exactly as for one with", () =>
      Effect.gen(function* () {
        const result = yield* attempt({ resetPasswordForEmail: { error: null } }, (auth) =>
          auth.requestPasswordReset({ email: credentials.email }),
        )

        assert.isTrue(Result.isSuccess(result))
      }),
    )

    it.effect("marks the link as a recovery, so the landing asks for a new password", () =>
      Effect.gen(function* () {
        const scripted = ScriptedAuthClient.make({ resetPasswordForEmail: { error: null } })

        yield* Effect.gen(function* () {
          const auth = yield* Auth.Auth
          return yield* Effect.result(auth.requestPasswordReset({ email: credentials.email }))
        }).pipe(provideAuth(scripted))

        assert.deepStrictEqual(
          scripted.calls.resetRedirects,
          ["https://example.test/auth/callback?flow=recovery"],
          "an unmarked recovery link drops the person into the app signed in, never asking for a new password",
        )
      }),
    )

    it.effect("reports RateLimited when asked again too soon", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { resetPasswordForEmail: { error: ScriptedAuthClient.authError("over_email_send_rate_limit") } },
          (auth) => auth.requestPasswordReset({ email: credentials.email }),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "RateLimited")
        }
      }),
    )
  })

  describe("setNewPassword", () => {
    it.effect("sends only the password, never an address", () =>
      Effect.gen(function* () {
        const scripted = ScriptedAuthClient.make({ updateUser: { error: null } })

        yield* Effect.gen(function* () {
          const auth = yield* Auth.Auth
          return yield* Effect.result(auth.setNewPassword({ password: credentials.password }))
        }).pipe(provideAuth(scripted))

        assert.deepStrictEqual(
          scripted.calls.updateUserAttributes,
          [{ password: "correct horse battery staple" }],
          "an address here would change the account's email rather than select which account to act on",
        )
      }),
    )

    /**
     * `otp_expired` is what a spent recovery link actually reports -- observed by following one twice against the local
     * stack, which came back `error_code=otp_expired`.
     */
    it.effect("maps expired and spent links to LinkInvalid", () =>
      Effect.gen(function* () {
        const outcomes = yield* Effect.forEach(
          ["otp_expired", "flow_state_expired", "flow_state_not_found"] as const,
          (code) =>
            attempt({ updateUser: { error: ScriptedAuthClient.authError(code) } }, (auth) =>
              auth.setNewPassword({ password: credentials.password }),
            ),
        )

        for (const result of outcomes) {
          assert.isTrue(Result.isFailure(result))
          if (Result.isFailure(result)) {
            assert.strictEqual(result.failure._tag, "LinkInvalid")
          }
        }
      }),
    )

    /**
     * Reuses the sign-up form's refusal rather than minting a second weak-password tag, so the two forms cannot drift
     * into refusing the same password for differently-worded reasons.
     */
    it.effect("reuses SignUpRejected/WeakPassword rather than a tag of its own", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { updateUser: { error: ScriptedAuthClient.authError("weak_password") } },
          (auth) => auth.setNewPassword({ password: credentials.password }),
        )

        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "SignUpRejected")
          assert.strictEqual((result.failure as Auth.SignUpRejected).reason, "WeakPassword")
        }
      }),
    )
  })

  describe("signInAnonymously", () => {
    it.effect("succeeds when the client reports no error", () =>
      Effect.gen(function* () {
        const result = yield* attempt({ signInAnonymously: { error: null } }, (auth) => auth.signInAnonymously)
        assert.isTrue(Result.isSuccess(result))
      }),
    )

    /**
     * The same resolved-not-rejected hazard the password paths pin: a disabled anonymous provider arrives as a RESOLVED
     * promise whose `error` is set, and must not read as "signed in".
     */
    it.effect("a disabled anonymous provider is a failure, not a silent success", () =>
      Effect.gen(function* () {
        const result = yield* attempt(
          { signInAnonymously: { error: ScriptedAuthClient.authError("anonymous_provider_disabled") } },
          (auth) => auth.signInAnonymously,
        )
        assert.isTrue(Result.isFailure(result))
        if (Result.isFailure(result)) {
          assert.strictEqual(result.failure._tag, "AuthError")
        }
      }),
    )
  })

  describe("signOut", () => {
    it.effect("signs out of this session only, never every device", () =>
      Effect.gen(function* () {
        const scripted = ScriptedAuthClient.make({ signOut: { error: null } })

        yield* Effect.gen(function* () {
          const auth = yield* Auth.Auth
          return yield* auth.signOut
        }).pipe(provideAuth(scripted))

        assert.deepStrictEqual(
          scripted.calls.signOutScopes,
          ["local"],
          "signOut fell back to the default global scope, which revokes the user's other devices",
        )
      }),
    )
  })
})
