// @tstyche template
//
// Proves that this package's row schemas still describe the live database.
//
// ## What is asserted, and why it is the COLUMN SET rather than the encoded type
//
// `supabase gen types` describes the **PostgREST/JSON API** shape. The application reads these
// tables through the Postgres driver instead, and the two disagree for good reasons: a `jsonb`
// column is `Json` over the API and a parsed value from the driver; a `timestamptz` is a string over
// the API and a `Date` from the driver.
//
// So `Schema.Codec.Encoded<typeof SomeRow>` is NOT equal to the generated `Row`, and asserting that
// it were would be asserting against the wrong oracle. What both descriptions genuinely agree on is
// which columns exist, and that is what drifts when someone adds, drops, or renames one, which is the
// failure this gate is for. A representation difference between two access paths is not a failure.
//
// If a table is ever read through `supabase-js` rather than SQL, THAT schema should additionally be
// asserted with `.type.toBe` against `Row`, because then PostgREST is the right oracle.
//
// ## Adding a table
//
// 1. write its row schema in `src/<Thing>Repo.ts`;
// 2. add `<table>: columnsOf("<Thing>Repo.<Thing>Row")` to `map` below, and the matching import to
//    `imports`;
// 3. regenerate the oracle (`nix run .#db-sync-supabase-local`) and run `pnpm test:types`.
//
// The `satisfies` on `map` is the exhaustiveness gate: a new table in the oracle with no `map` entry
// is a compile error HERE, in the template, before any generated test runs.

import * as Array from "effect/Array"
import { pipe } from "effect/Function"
import * as Record from "effect/Record"
import * as String from "effect/String"

import type { Database } from "../src/internal/supabase-database.js"

/**
 * Tables this package does not model.
 *
 * `effect_sql_migrations` is bookkeeping the migrator creates and maintains for itself. Nothing declares its shape: the
 * migrator owns it end to end, and a row schema mirroring it would be a second description of a table no query of ours
 * names. A table another runtime creates in `public` belongs on this list for the same reason.
 */
type OwnedTables = Omit<Database["public"]["Tables"], "effect_sql_migrations">

const imports = `
import { expect, test } from "tstyche"
import type { Database } from "../src/internal/supabase-database.js"
import * as Schema from "effect/Schema"

type ColumnsOf<S> = keyof Schema.Codec.Encoded<S>
type RowColumns<T extends keyof Database["public"]["Tables"]> =
  keyof Database["public"]["Tables"][T]["Row"]
type OwnedTables = Omit<Database["public"]["Tables"], "effect_sql_migrations">
`

const columnsOf = <const T extends string>(s: T) => `ColumnsOf<typeof ${s}>` as const

/**
 * One entry per owned table: the table name to the row schema's column set, spelled through {@link columnsOf}. The
 * `satisfies` makes a NEW table with no entry a compile error in this template, rather than a table nobody remembered
 * to check.
 */
const map = {} as const satisfies { [K in keyof OwnedTables]: ReturnType<typeof columnsOf> }

const tables: ReadonlyArray<readonly [table: string, columns: string]> = pipe(
  map,
  Record.collect((table, columns) => [table, columns] as const),
)

/**
 * The generated file always carries at least this test, so a run with no owned tables still asserts something: that the
 * oracle names exactly the tables the map does. An owned table the map has no entry for cannot reach here (the
 * `satisfies` above stops it), and a map entry for a table the oracle no longer has fails this assertion.
 */
const coverage = `
test("the map names every owned table", () =>
  expect<keyof OwnedTables>().type.toBe<${
    tables.length === 0
      ? "never"
      : pipe(
          tables,
          Array.map(([table]) => `"${table}"`),
          Array.join(" | "),
        )
  }>())
`

const columnSets = pipe(
  tables,
  Array.map(
    ([table, columns]) => `
    test("${columns} covers ${table} exactly", () =>
      expect<${columns}>().type.toBe<RowColumns<"${table}">>())
  `,
  ),
  Array.join("\n"),
)

export default pipe(imports, String.concat(coverage), String.concat(columnSets))
