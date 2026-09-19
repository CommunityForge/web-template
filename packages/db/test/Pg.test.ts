import * as PgTypes from "@effect/sql-pg/PgTypes"
import { describe, it } from "@effect/vitest"
import { assertFailure, assertSuccess } from "@effect/vitest/utils"
import * as Pg from "@replaceme/db/Pg"

// OID 40000: its wire bytes hold 0x9c, a UTF-8 continuation byte with no lead byte, so a
// registry that reads them as text rejects the row. Any table created after enough others
// gets an identifier like this; a fresh `supabase start` already does.
const regclassBytes = new Uint8Array([0x00, 0x00, 0x9c, 0x40])

describe("Pg.types", () => {
  it("decodes a regclass column as its OID number", () => {
    assertSuccess(PgTypes.decode(regclassBytes, Pg.REGCLASS_OID, 1, Pg.types), 40000)
  })

  it("encodes a regclass parameter as the four-byte OID", () => {
    assertSuccess(PgTypes.encode(40000, Pg.REGCLASS_OID, Pg.types), regclassBytes)
  })

  it("rejects a regclass value that is not an OID", () => {
    assertFailure(
      PgTypes.encode(-1, Pg.REGCLASS_OID, Pg.types),
      new PgTypes.CodecError({ message: "Expected an integer between 0 and 4294967295 for regclass, received -1" }),
    )
  })

  it("is the built-in registry's gap: without it the same bytes are rejected", () => {
    assertFailure(
      PgTypes.decode(regclassBytes, Pg.REGCLASS_OID, 1),
      new PgTypes.CodecError({ message: "Invalid UTF-8 in text value" }),
    )
  })
})
