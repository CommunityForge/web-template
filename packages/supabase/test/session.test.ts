/* `as never` here builds deliberately partial test doubles: the assertions exercise one field of a wide third-party
 * payload, and spelling the rest out would assert nothing while coupling the test to the vendor's shape. */
/* eslint-disable typescript/no-unsafe-type-assertion */
/**
 * The pin on the adapter's containment promise.
 *
 * `packages/domain/src/Auth.ts` states it as a design rule — "Tokens are deliberately absent… Refresh tokens never
 * leave the adapter" — but a rule stated in prose is enforced by nothing. `fromSupabase` is the single door the
 * supabase-js session passes through on its way into the domain, so this is where the rule can actually be checked.
 */

import { assert, describe, it } from "@effect/vitest"
import * as Option from "effect/Option"

import * as internalSession from "../src/internal/session.js"

const userId = "6b1f1a3e-6f5a-4c2e-9f2a-7f3d5c8b1e40"

/**
 * A session shaped as supabase-js hands it over, tokens and all.
 */
const supabaseSession = {
  access_token: "ACCESS-TOKEN-SHOULD-NOT-ESCAPE",
  refresh_token: "REFRESH-TOKEN-SHOULD-NOT-ESCAPE",
  provider_token: "PROVIDER-TOKEN-SHOULD-NOT-ESCAPE",
  provider_refresh_token: "PROVIDER-REFRESH-SHOULD-NOT-ESCAPE",
  token_type: "bearer",
  expires_in: 3600,
  expires_at: 1_800_000_000,
  user: {
    id: userId,
    email: "member@example.com",
    created_at: "2026-01-01T00:00:00.000Z",
  },
}

describe("internal/session.fromSupabase", () => {
  it("projects the user and expiry, and nothing else", () => {
    const decoded = internalSession.fromSupabase(supabaseSession as never)

    assert.isTrue(Option.isSome(decoded), "a well-formed session failed to decode")
    if (Option.isNone(decoded)) return

    assert.deepStrictEqual(
      new Set(Object.keys(decoded.value)),
      new Set(["expiresAt", "user"]),
      "the domain Session grew a field — check it is not carrying token material",
    )
    assert.strictEqual(decoded.value.user.id, userId)
    assert.deepStrictEqual(decoded.value.user.email, Option.some("member@example.com"))
  })

  it("carries no token material anywhere in its serialized form", () => {
    const decoded = internalSession.fromSupabase(supabaseSession as never)
    if (Option.isNone(decoded)) {
      assert.fail("a well-formed session failed to decode")
      return
    }

    // Serialized rather than key-checked, because a token could hide at any depth — this is the assertion that would
    // catch someone widening the projection to `...raw`.
    const serialized = JSON.stringify(decoded.value)
    assert.isFalse(serialized.includes("SHOULD-NOT-ESCAPE"), `token material reached the domain Session: ${serialized}`)
  })

  it("treats a null session as signed out rather than failing", () => {
    assert.isTrue(Option.isNone(internalSession.fromSupabase(null)))
  })

  /**
   * The regression this file exists to prevent a second time.
   *
   * GoTrue reports an anonymous user's address as PRESENT AND EMPTY, never absent, so `Option.fromNullishOr` admitted
   * `Some("")` into `User.User.make` — whose `email` is `Schema.Option(Schema.Trimmed & isNonEmpty)`. `make` throws,
   * and the throw happened inside `SupabaseAuth.layer`'s construction, where the app's one `Layer.orDie` turned it into
   * a store that never launched at all. Once ensure-session began minting an anonymous session for every fresh visitor,
   * that was every first load.
   *
   * The whitespace case rides along because the domain asks for `Trimmed` as well as non-empty: lifting on `=== ""`
   * alone would let `" "` through to the same throw.
   */
  it.each([
    ["an anonymous user's empty email", ""],
    ["a whitespace-only email", "   "],
  ])("reads %s as no address rather than throwing", (_label, email) => {
    const decoded = internalSession.fromSupabase({
      ...supabaseSession,
      user: { ...supabaseSession.user, email },
    } as never)

    assert.isTrue(Option.isSome(decoded), "an anonymous session failed to decode — this is the outage, not a nicety")
    if (Option.isNone(decoded)) return

    assert.deepStrictEqual(decoded.value.user.email, Option.none())
    assert.strictEqual(decoded.value.user.id, userId)
  })

  /**
   * The property the `makeOption` / `DateTime.make` rewrite establishes, pinned as a property rather than as the one
   * shape that happened to break.
   *
   * `fromSupabase` returns `Option`, and its whole job is that a session it cannot read is `None` — never a throw. That
   * mattered because the one caller is `SupabaseAuth.layer`'s CONSTRUCTION, where a throw becomes a defect that
   * `AppLive`'s `Layer.orDie` escalates into an app that does not start. A `_tag`-shaped assertion would have missed
   * the original bug; "does not throw, for any input" would not have.
   */
  it.each([
    ["a non-UUID id", { ...supabaseSession, user: { ...supabaseSession.user, id: "not-a-uuid" } }],
    ["a missing user", { ...supabaseSession, user: undefined }],
    ["an unparsable created_at", { ...supabaseSession, user: { ...supabaseSession.user, created_at: "yesterday" } }],
    ["a NaN expiry", { ...supabaseSession, expires_at: undefined, expires_in: Number.NaN }],
    ["an infinite expiry", { ...supabaseSession, expires_at: Number.POSITIVE_INFINITY }],
    ["an entirely foreign shape", { nonsense: true }],
    ["a primitive", 42],
  ])("reads %s as None rather than throwing", (_label, input) => {
    const decoded = internalSession.fromSupabase(input as never)
    assert.isTrue(Option.isNone(decoded), "malformed input produced a session instead of None")
  })

  /**
   * The domain's claim is that a present address is a real one, so the adapter must not quietly hand back padding.
   */
  it("trims a padded address rather than passing it through", () => {
    const decoded = internalSession.fromSupabase({
      ...supabaseSession,
      user: { ...supabaseSession.user, email: "  member@example.com  " },
    } as never)

    assert.isTrue(Option.isSome(decoded))
    if (Option.isNone(decoded)) return
    assert.deepStrictEqual(decoded.value.user.email, Option.some("member@example.com"))
  })
})
