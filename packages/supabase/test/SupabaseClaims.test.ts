/**
 * What a verified Supabase token is allowed to become.
 *
 * The JWKS layer proves a token was signed by the project; this module decides whether that token describes a _user_.
 * The two are not the same question — a project signs several classes of credential — so these cases pin the ones that
 * must not turn into a principal.
 */

import { assert, describe, it } from "@effect/vitest"
import * as CurrentUser from "@replaceme/domain/CurrentUser"
import * as SupabaseClaims from "@replaceme/supabase/SupabaseClaims"
import * as Effect from "effect/Effect"
import * as Option from "effect/Option"
import * as Result from "effect/Result"
import * as Schema from "effect/Schema"

const userId = "6b1f1a3e-6f5a-4c2e-9f2a-7f3d5c8b1e40"

/**
 * A permanent, signed-in user as Supabase describes one.
 */
const permanent = {
  sub: userId,
  aud: "authenticated",
  role: "authenticated",
  is_anonymous: false,
  email: "member@example.com",
  session_id: "0f0d6d0e-4d1e-4a54-9b8a-1a1f2f6d9c31",
}

const decodeOpaque = SupabaseClaims.toPrincipal(Schema.Unknown)

const attempt = (claims: unknown) => Effect.result(decodeOpaque(claims))

describe("SupabaseClaims.toPrincipal", () => {
  it.effect("decodes a permanent user", () =>
    Effect.gen(function* () {
      const result = yield* attempt(permanent)

      assert.isTrue(Result.isSuccess(result), "a well-formed user token was rejected")
      if (Result.isSuccess(result) && CurrentUser.AuthPrincipal.$is("Member")(result.success)) {
        assert.strictEqual(result.success.userId, userId)
        assert.deepStrictEqual(result.success.email, Option.some("member@example.com"))
      } else {
        assert.fail("a permanent token did not decode to a Member principal")
      }
    }),
  )

  it.effect("admits an anonymous user, and says so", () =>
    Effect.gen(function* () {
      // Anonymous users carry the same `authenticated` role. Rejecting them here would be a policy decision this
      // module does not get to make; hiding the identity would stop the route from making it either.
      const result = yield* attempt({ ...permanent, is_anonymous: true, email: null })

      assert.isTrue(Result.isSuccess(result))
      if (Result.isSuccess(result)) {
        assert.isTrue(CurrentUser.AuthPrincipal.$is("Anonymous")(result.success))
        assert.isTrue(CurrentUser.isAnonymous(result.success))
      }
    }),
  )

  it.effect("admits the guest shape the provider actually emits: a present but empty address", () =>
    Effect.gen(function* () {
      // A guest's address arrives as `""`, not as `null`. A decoder lifting only nullish values would classify every
      // real guest by a non-empty address it does not have — which is every anonymous session.
      const result = yield* attempt({ ...permanent, is_anonymous: true, email: "" })

      assert.isTrue(Result.isSuccess(result), "the provider's own guest shape was rejected")
      if (Result.isSuccess(result)) {
        assert.isTrue(CurrentUser.isAnonymous(result.success))
      }
    }),
  )

  it.effect("a blank address on a member is absent, never a present empty string", () =>
    Effect.gen(function* () {
      const result = yield* attempt({ ...permanent, email: "   " })

      assert.isTrue(Result.isSuccess(result))
      if (Result.isSuccess(result) && CurrentUser.AuthPrincipal.$is("Member")(result.success)) {
        assert.deepStrictEqual(result.success.email, Option.none())
      } else {
        assert.fail("a permanent token did not decode to a Member principal")
      }
    }),
  )

  it.effect("rejects a token whose role is not a user role", () =>
    Effect.gen(function* () {
      // The shape of the publishable anon key, and of a service_role token: signed by the project, not a user.
      const result = yield* attempt({ ...permanent, role: "anon" })

      assert.isTrue(Result.isFailure(result), "an `anon` role token became a user principal")
      if (Result.isFailure(result)) {
        assert.strictEqual(result.failure._tag, "Unauthorized")
      }
    }),
  )

  it.effect("rejects a token with no subject", () =>
    Effect.gen(function* () {
      const { sub: _sub, ...withoutSub } = permanent
      const result = yield* attempt(withoutSub)

      assert.isTrue(Result.isFailure(result))
    }),
  )

  it.effect("rejects a subject that is not a UUID", () =>
    Effect.gen(function* () {
      // `userId` flows into repositories as an ownership key, so an arbitrary string must not reach one.
      const result = yield* attempt({ ...permanent, sub: "../../etc/passwd" })

      assert.isTrue(Result.isFailure(result), "a non-UUID subject became a UserId")
    }),
  )

  it.effect("rejects a token missing the anonymity discriminator", () =>
    Effect.gen(function* () {
      const { is_anonymous: _isAnonymous, ...withoutFlag } = permanent
      const result = yield* attempt(withoutFlag)

      assert.isTrue(Result.isFailure(result), "a token we cannot classify was accepted")
    }),
  )

  it.effect("carries no claim material into the failure", () =>
    Effect.gen(function* () {
      const result = yield* attempt({ ...permanent, role: "service_role", email: "leak@example.com" })

      assert.isTrue(Result.isFailure(result))
      if (Result.isFailure(result)) {
        assert.isFalse(
          JSON.stringify(result.failure).includes("leak@example.com"),
          "Unauthorized echoed the rejected claims back to the caller",
        )
      }
    }),
  )

  it.effect("decodes app_metadata through the schema the caller supplied", () =>
    Effect.gen(function* () {
      // The seam the tiering work plugs into: the package fixes the envelope, the domain names the payload.
      const decode = SupabaseClaims.toPrincipal(Schema.Struct({ tier: Schema.Literals(["free", "paid"]) }))

      const accepted = yield* Effect.result(decode({ ...permanent, app_metadata: { tier: "paid" } }))
      assert.isTrue(Result.isSuccess(accepted))
      if (Result.isSuccess(accepted)) {
        assert.deepStrictEqual(accepted.success.appMetadata, Option.some({ tier: "paid" }))
      }

      const rejected = yield* Effect.result(decode({ ...permanent, app_metadata: { tier: "enterprise" } }))
      assert.isTrue(Result.isFailure(rejected), "an unknown tier decoded instead of failing")
    }),
  )
})
