import * as Option from "effect/Option"
import * as Predicate from "effect/Predicate"
import * as Schema from "effect/Schema"

export const Password = Schema.Redacted(Schema.String.pipe(Schema.brand("Password")))
export type Password = typeof Password.Type

/**
 * Supabase mints `sub` as a UUID, so an id that is not one did not come from a token we issued. The check matters
 * because this value flows straight into SQL repositories as an ownership key — a brand alone would let any string
 * through.
 */
export const UserId = Schema.String.pipe(Schema.check(Schema.isUUID()), Schema.brand("UserId"))
export type UserId = typeof UserId.Type

export class User extends Schema.TaggedClass<User>("@replaceme/domain/User")("User", {
  id: UserId,
  email: Schema.Option(Schema.Trimmed.pipe(Schema.check(Schema.isNonEmpty()))),
  createdAt: Schema.Union([Schema.DateTimeUtcFromString, Schema.DateTimeUtc]),
}) {}

/**
 * A guest identity, as distinct from an account.
 *
 * The absent address is the only signal a browser has: GoTrue reports an anonymous user with an email that is present
 * and empty, which `@replaceme/supabase`'s session decoder lifts to `None` precisely so the two are distinguishable.
 * Both identities carry the same `authenticated` role, so the role cannot be asked.
 *
 * @since 0.0.0
 * @category predicates
 */
export const isAnonymous = (user: User): boolean => Option.isNone(user.email)

/**
 * @since 0.0.0
 * @category predicates
 */
export const isMember: (user: User) => boolean = Predicate.not(isAnonymous)

export class UserNotFound extends Schema.TaggedError<UserNotFound>("@replaceme/domain/UserNotFound")("UserNotFound", {
  id: UserId,
}) {}
