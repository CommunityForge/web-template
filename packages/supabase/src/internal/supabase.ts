import * as Option from "effect/Option"
import * as Schema from "effect/Schema"
import * as SchemaTransformation from "effect/SchemaTransformation"

export const UserId = Schema.String.pipe(Schema.brand("UserId"))
export type UserId = typeof UserId.Type

const NonEmptyTrimmedString = Schema.Trimmed.check(Schema.isNonEmpty())

const OptionFromNonEmptyTrimmedString = Schema.String.pipe(
  Schema.decodeTo(
    Schema.Option(NonEmptyTrimmedString),
    SchemaTransformation.transform({
      decode: (s: string) => {
        const t = s.trim()
        return t.length === 0 ? Option.none() : Option.some(t)
      },
      encode: Option.getOrElse(() => ""),
    }),
  ),
)

export class SupabaseUserAppMetadata extends Schema.Class<SupabaseUserAppMetadata>("SupabaseUserAppMetadata")({
  provider: Schema.OptionFromOptional(Schema.NonEmptyString),
  // [key: string]: any
}) {}

export class SupabaseUserMetadata extends Schema.Class<SupabaseUserMetadata>("SupabaseUserMetadata")({
  provider: Schema.OptionFromOptional(Schema.NonEmptyString),
  // [key: string]: any
}) {}

export class SupabaseUserIdentity extends Schema.Class<SupabaseUserIdentity>("SupabaseUserIdentity")({
  id: Schema.NonEmptyString,
  user_id: Schema.NonEmptyString,
  identity_data: Schema.OptionFromOptional(Schema.JsonObject),
  identity_id: Schema.NonEmptyString,
  provider: Schema.NonEmptyString,
  created_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  last_sign_in_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  updated_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
}) {}

export class SupabaseFactor extends Schema.Class<SupabaseFactor>("SupabaseFactor")({
  id: Schema.NonEmptyString.pipe(
    Schema.annotate({
      description: "ID of the factor",
    }),
  ),
  friendly_name: Schema.OptionFromOptional(
    Schema.NonEmptyString.pipe(
      Schema.annotate({
        description: "Friendly name of the factor, useful to disambiguate between multiple factors.",
      }),
    ),
  ),
  factor_type: Schema.Union([Schema.Literal("totp"), Schema.Literal("phone"), Schema.String]).pipe(
    Schema.annotate({
      description: "Type of factor. `totp` and `phone` supported with this version",
    }),
  ),
  status: Schema.Union([Schema.Literal("verified"), Schema.Literal("unverified")]),
  created_at: Schema.DateTimeUtc,
  updated_at: Schema.DateTimeUtc,
}) {}

export class SupabaseUser extends Schema.Class<SupabaseUser>("SupabaseUser")({
  id: UserId,
  app_metadata: SupabaseUserAppMetadata,
  user_metadata: SupabaseUserMetadata,
  aud: Schema.NonEmptyString,
  confirmation_sent_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  recovery_sent_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  email_change_sent_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  new_email: Schema.OptionFromOptional(Schema.NonEmptyString),
  new_phone: Schema.OptionFromOptional(Schema.NonEmptyString),
  invited_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  action_link: Schema.OptionFromOptional(Schema.NonEmptyString),
  email: Schema.OptionFromOptional(Schema.NonEmptyString),
  phone: Schema.OptionFromOptional(OptionFromNonEmptyTrimmedString),
  created_at: Schema.DateTimeUtc,
  confirmed_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  email_confirmed_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  phone_confirmed_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  last_sign_in_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  role: Schema.OptionFromOptional(Schema.NonEmptyString),
  updated_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
  identities: Schema.OptionFromOptional(Schema.Array(SupabaseUserIdentity)),
  is_anonymous: Schema.OptionFromOptional(Schema.Boolean),
  is_sso_user: Schema.OptionFromOptional(Schema.Boolean),
  factors: Schema.OptionFromOptional(Schema.Array(SupabaseFactor)),
  deleted_at: Schema.OptionFromOptional(Schema.DateTimeUtc),
}) {}

export class SupabaseError extends Schema.TaggedError<SupabaseError>("Supabase/SupabaseError")("SupabaseError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

export const User = Schema.Struct({
  created_at: Schema.DateTimeZoned,
  email: NonEmptyTrimmedString,
  id: Schema.String.check(Schema.isUUID()),
  updated_at: Schema.DateTimeZoned,
})
export type User = typeof User.Type
