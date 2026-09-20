import { describe, it } from "@effect/vitest"
import { deepStrictEqual, strictEqual } from "@effect/vitest/utils"
import * as User from "@replaceme/domain/User"
import * as DateTime from "effect/DateTime"
import * as Effect from "effect/Effect"
import * as Option from "effect/Option"
import * as Schema from "effect/Schema"

const decodeUserId = Schema.decodeUnknownEffect(User.UserId)

const uuid = "8d2b1a6e-5f0c-4c3a-9d7e-2b1f0a9c8d7e"

describe("User", () => {
  describe("UserId", () => {
    it.effect("decodes a UUID", () =>
      Effect.gen(function* () {
        const id = yield* decodeUserId(uuid)
        strictEqual(id, uuid)
      }),
    )

    it.effect("rejects a string that is not a UUID", () =>
      Effect.gen(function* () {
        const error = yield* Effect.flip(decodeUserId("not-a-uuid"))
        strictEqual(error._tag, "SchemaError")
      }),
    )
  })

  describe("isAnonymous / isMember", () => {
    const user = (email: Option.Option<string>) =>
      User.User.make({
        id: Schema.decodeSync(User.UserId)(uuid),
        email,
        createdAt: DateTime.makeUnsafe(0),
      })

    it("a user with no address is anonymous", () => {
      const guest = user(Option.none())
      strictEqual(User.isAnonymous(guest), true)
      strictEqual(User.isMember(guest), false)
    })

    it("a user with an address is a member", () => {
      const member = user(Option.some("member@example.com"))
      strictEqual(User.isAnonymous(member), false)
      strictEqual(User.isMember(member), true)
    })
  })

  describe("UserNotFound", () => {
    it.effect("is a failure carrying the id", () =>
      Effect.gen(function* () {
        const id = yield* decodeUserId(uuid)
        const error = yield* Effect.flip(Effect.fail(new User.UserNotFound({ id })))
        deepStrictEqual(error, new User.UserNotFound({ id }))
      }),
    )
  })
})
