/**
 * Decode `supabase-js` session objects into the domain `Session`.
 *
 * @internal
 */

import type * as SupabaseJs from "@supabase/supabase-js"

import * as Auth from "@replaceme/domain/Auth"
import * as User from "@replaceme/domain/User"
import * as DateTime from "effect/DateTime"
import * as Option from "effect/Option"
import * as Schema from "effect/Schema"

const SupabaseSession = Schema.Struct({
  /**
   * epoch seconds
   */
  expires_at: Schema.optional(Schema.Finite),
  user: Schema.Struct({
    id: User.UserId,
    email: Schema.optional(Schema.String),
    created_at: Schema.DateTimeUtcFromString,
  }),
})

const decode = Schema.decodeUnknownOption(SupabaseSession)

/**
 * "No email" reaches us as THREE encodings, and only two of them are nullish.
 *
 * `User.email` is `Schema.Option(Schema.Trimmed & isNonEmpty)` -- the domain's claim is that an address, when present,
 * is a real one -- and `Option.fromNullishOr` alone honors `null`/`undefined` while passing `""` straight through as
 * `Some("")`. GoTrue reports an ANONYMOUS user exactly that way: `email` is present and empty, never absent. So the
 * lift has to be on emptiness, not on nullishness, and it has to trim first because `Schema.Trimmed` rejects the padded
 * forms that would otherwise survive the length check.
 *
 * This was not a latent nicety. It raised `Expected a value with a length of at least 1, got ""` out of
 * `User.User.make`, and since ensure-session started minting an anonymous user for every fresh visitor, the very next
 * `getSession` restored one and took the whole store down.
 *
 * Note the two fixes are independent and both belong: {@link fromSupabase} is now total, so a bad address yields `None`
 * instead of a throw -- but `None` means SIGNED OUT, and an anonymous user is signed IN. Only this lift gets the
 * meaning right; totality alone would have traded a dead store for a silently unauthenticated one.
 */
const emailOf = (email: string | undefined): Option.Option<string> =>
  Option.filter(
    Option.map(Option.fromNullishOr(email), (raw) => raw.trim()),
    (trimmed) => trimmed.length > 0,
  )

/**
 * GoTrue's `expires_at` is epoch SECONDS and optional; `expires_in` is the relative fallback it always sends. Neither
 * is validated by the decode above (`expires_in` is read off the raw session), so this can produce `NaN` -- which is
 * precisely why the caller lifts it through `DateTime.make` rather than `makeUnsafe`.
 */
const expiresAtMillis = (expiresAt: number | undefined, expiresIn: number): number =>
  (expiresAt ?? expiresIn + Date.now() / 1000) * 1000

/**
 * TOTAL: every step is `Option`, so this function cannot throw and cannot produce a defect.
 *
 * It used to be built from the THROWING constructors -- `User.User.make`, `Auth.Session.make`, `DateTime.makeUnsafe` --
 * inside a function whose return type already said `Option`, i.e. whose signature already claimed the failure was
 * modeled. It was not: a session this adapter could not read raised a defect from inside `SupabaseAuth.layer`'s
 * construction, and `AppLive`'s `Layer.orDie` turned that into a store that never launched. An anonymous user's `email:
 * ""` was enough.
 *
 * `Schema.Class` and `Schema.TaggedClass` both expose `makeOption` (and `makeEffect`) beside the throwing `make`, and
 * `DateTime.make` is the `Option`-returning twin of `makeUnsafe`. Using them is not defensive coding -- it is the
 * signature becoming true. A supabase session that does not fit the domain is an EXPECTED boundary condition, not a
 * broken invariant, so per the error-handling guide it belongs in the value channel rather than in a `Cause.Die` that
 * something further out has to catch.
 *
 * `Option.all` is the conjunction: the session exists only if BOTH the user and the expiry do.
 *
 * NOTE the arrow around `Session.makeOption`. It is a `static` method that reads `getClassSchema(this)`, so handing it
 * to `Option.flatMap` point-free detaches `this` and it throws a TypeError from inside the schema parser -- which
 * `makeOption` then reports as `Option adapter can only return none for schema issues`, because a TypeError is a defect
 * rather than a schema issue. Exactly the class of throw this function exists to not have.
 */
export const fromSupabase = (session: SupabaseJs.Session | null): Option.Option<Auth.Session> =>
  Option.flatMap(Option.fromNullishOr(session), (raw) =>
    Option.flatMap(decode(raw), (decoded) =>
      Option.flatMap(
        Option.all({
          user: User.User.makeOption({
            id: decoded.user.id,
            email: emailOf(decoded.user.email),
            createdAt: decoded.user.created_at,
          }),
          expiresAt: DateTime.make(expiresAtMillis(decoded.expires_at, raw.expires_in)),
        }),
        (fields) => Auth.Session.makeOption(fields),
      ),
    ),
  )
