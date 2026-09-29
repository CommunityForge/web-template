import { describe, it } from "@effect/vitest"
import { strictEqual } from "@effect/vitest/utils"
import * as Greeting from "@landbank/lib/Greeting"

describe("Greeting", () => {
  it("renders a greeting", () => {
    strictEqual(Greeting.make("world"), "Hello, world!")
  })
})
