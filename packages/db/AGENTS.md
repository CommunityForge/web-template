# packages/db

Postgres: the client layer (`Pg`), the schema (DDL authored in TypeScript and applied by Effect's migrator), the
standing exposure audit (`bin/audit.ts`), and the repositories over the tables, one module per table family. It ships
no table today; the recipe below is what the first one follows.

`@replaceme/domain` is the one workspace dependency: repositories are typed in terms of the domain's branded ids and
never re-declare a shape. The database is named one of two ways through the ambient `ConfigProvider`, with no defaults,
so a missing credential stops the process rather than quietly connecting somewhere: the five `DB_*` variables
(`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWD`, `DB_DATABASE`) as `Pg.PgLive`, or one `DB_URL` connection string as
`Pg.PgUrlLive`. `Pg.PgAutoLive` takes `DB_URL` when it is set and the five otherwise, and is what the operator programs
use, so the same binary runs against local Supabase and against a hosted branch's session pooler. The `supabase` CLI is
needed for the drift gate's oracle only; nothing at runtime uses it.

## Commands

| Command                            | Does                                                         |
| ---------------------------------- | ------------------------------------------------------------ |
| `nix run .#db-migrate`             | Apply pending migrations, report what was applied, exit      |
| `nix run .#db-audit`               | Exit non-zero if an exposed table lacks row security         |
| `nix run .#db-reset`               | `supabase db reset`, then migrate, then audit                |
| `nix run .#db-sync-supabase-local` | Regenerate `src/internal/supabase-database.ts` from local DB |
| `nix run .#db-migrator`            | Migrate, then audit, with no workspace: `DB_URL` or `DB_*`   |

The apps export local-Supabase `DB_*` values; set them in the environment to point elsewhere. A full local rebuild is
`db-reset`, in that order: a user-owned table references `auth.users`, which only exists after Supabase's reset, and a
reset restores Supabase's stock default privileges, so the lockdown is re-applied and re-checked rather than assumed.

`db-migrator` is a package, not an app: `build:bin` bundles `bin/migrate.ts` and `bin/audit.ts` with esbuild into
`build/`, one self-contained module each importing only `node:*`, and the package runs them with the Node it was built
against. It exports no `DB_*` defaults, so it runs only where the environment names a database, which is the point: a
CI job with nothing installed points `DB_URL` at a hosted branch's session pooler and runs it straight from `nix run`.

## A repository, module for module

`<Thing>Repo.ts`, one per table family:

```ts
export class ThingRepo extends Context.Service<
  ThingRepo,
  {
    // Written out, not inferred from `make`: this is the published surface, and the error channel is part of it.
    readonly findAll: (
      userId: User.UserId,
    ) => Effect.Effect<ReadonlyArray<Thing>, SqlError.SqlError | Schema.SchemaError>
  }
>()("@replaceme/db/ThingRepo", {
  make: Effect.gen(function* () {
    const sql = yield* SqlClient.SqlClient
    const rows = SqlSchema.findAll({ Request: User.UserId, Result: ThingRow, execute: (userId) => sql`...` })
    const findAll = Effect.fn("ThingRepo.findAll")(function* (userId: User.UserId) {
      /* ... */
    })
    return { findAll } as const
  }),
}) {
  static readonly Live = Layer.effect(this)(this.make)
}
```

The service requires only `SqlClient`, which is what makes it constructible in a test from a bare client and callable
from an operator program.

- **`userId` is an argument, never a dependency**, on every method touching a user-owned table. The layer above reads
  the request's principal and passes it down; the repository stays free of request context. This is also the access
  control that fires: the application connects as the owner role, which bypasses row security, so the
  `where user_id = ${userId}` in the statement is the real guard and the policy is defense in depth.
- **Decode, never cast.** Reads go through `SqlSchema.findAll` / `findOne` / `findOneOption` with `Request` and
  `Result` schemas. A `sql<{ ... }>` type parameter asserts driver output rather than checking it, so it appears only
  where the sole fact consumed is `rows.length`. `.raw` hands back the driver's result object as `unknown`, decoded
  through a schema with a REQUIRED `rowCount`: defaulting an absent count to `0` would make a driver regression look
  like "nothing to do".
- **Row schemas are typed for the DRIVER.** A `jsonb` column arrives parsed, a `timestamptz` as a `Date`
  (`Schema.DateTimeUtcFromDate`); a JSON API over the same table would serialize both as strings. Verify a column's
  materialized shape against a running database before spelling its schema. A row schema stays a faithful description
  of the table: a column the domain has no slot for is dropped in the row-to-domain fold, not omitted from the schema.
- **`jsonb` columns go through `Schema.toCodecJson`.** A bare schema's Encoded side still holds `Option` and `Date`
  instances that `JSON.stringify` flattens into shapes the bare codec then rejects on read. Derive the JSON codec rather
  than trusting the Encoded side to happen to be JSON-safe. Prefer `jsonb` where the value's own union already
  expresses the shape, over flat columns with an "exactly one is null" rule.
- **Writes state their conflict rule in SQL, at the statement.** Idempotent insert: `on conflict (k) do nothing ...
returning id`, mapped to a boolean the caller decides about. Supersession: `on conflict (k) do update set ... where
(excluded.a, excluded.b) > (t.a, t.b)`, a lexicographic tuple with strict `>` so a re-run writes nothing. One writer
  per column, so independent writers interleave without a read-modify-write. A cross-user guard
  `where t.user_id = ${userId}` on the conflict arm. Bulk: one `jsonb` parameter expanded by `jsonb_to_recordset(...)
as t(col type, ...)` with explicit casts, deduplicated with `distinct on (key)` and an `order by` mirroring the
  conflict rule. Multi-statement reconciliation is `sql.withTransaction`. `sql.in` needs a non-empty array, so the
  empty case is a separate statement.

## Migrations

One file per migration, `src/migrations/<id>_<name>.ts`, exporting `migration` (an `Effect.gen` that acquires
`SqlClient` and yields raw DDL), plus a key in `Migrator.ts`'s `fromRecord`. Keys apply in id order. An applied
migration is immutable: change the schema by adding a file and a key.

Applying DDL is an operational boundary: `bin/migrate.ts` is a program an operator runs, and nothing on a request path
reaches it. GoTrue owns `auth.*`; this package owns `public`, through its own `effect_sql_migrations` ledger.

DDL comments carry what a column type cannot: a value's frame, unit, and which normalization a text key has already had
applied.

### A user-owned table carries ownership three times

`user_id uuid not null references auth.users (id) on delete cascade`; row security enabled with a policy whose predicate
is `user_id = (select auth.uid())` (the `select` evaluates once per query, not per row); and the query-level scope in
the repository. The query-level scope fires today; the policy protects any future path that reaches the table as an
unprivileged role.

### Exposure is opt-in, and audited

Two independent things decide what PostgREST's `anon` / `authenticated` roles can do: a `grant` decides whether the
role reaches a table at all, and row security plus a policy decides which rows it sees once in. The invariant is
therefore **every table in an exposed schema is either ungranted, or granted AND RLS-enabled AND has a policy**. A
`grant` and its policy belong in the same migration.

`0001_data_api_lockdown` revokes everything from those roles across `public` and sets `alter default privileges` to
keep revoking, so a new table is unreachable until a migration grants it. That statement covers objects created by the
role it names; a second connecting role means repeating it. `bin/audit.ts` is the standing check and exits non-zero on
any violation; keep its `EXPOSED_SCHEMAS` matching `supabase/config.toml`'s `[api] schemas` by hand, because it states
what SHOULD be exposed and a drift between the two is itself the finding.

## Tests

`test/Supabase.tst.ts` is the drift gate, a tstyche template run by `pnpm test:types` and invisible to vitest. tstyche
needs TypeScript's JavaScript compiler API, which the repo's native `typescript` build does not ship, and it downloads
compilers from the registry unless told which module to load; `test:types` therefore points `TSTYCHE_TYPESCRIPT_MODULE`
at `tstyche-typescript`, a TypeScript 5 alias in `devDependencies`, so the run is offline and works inside the Nix
sandbox. It asserts the COLUMN SET of every owned table against `src/internal/supabase-database.ts`, the description Supabase
generates of the live schema, because the column set is what both the driver-typed row schema and the API-typed oracle
agree on and what drifts when a column is added, dropped or renamed. A representation difference between the two access
paths is not a failure.

The oracle is generated output. Regenerate it with `nix run .#db-sync-supabase-local` against a local Supabase that has
had `db-reset` run; the file is never edited by hand and never written from memory.

**A table change is complete only when all four agree:** the row schema in `src/<Thing>Repo.ts`, the `map` entry in the
template (`<table>: columnsOf("<Thing>Repo.<Thing>Row")` plus the import in the template's `imports` string), the
regenerated oracle, and a green `pnpm test:types`. The template's `satisfies` turns an owned table with no `map` entry
into a compile error in the template itself, before any generated test runs; a table another runtime creates in
`public` joins `effect_sql_migrations` in the `OwnedTables` exclusion instead.

Vitest suites, when a repository lands, follow the root rules and mirror `src` file for file (`test/ThingRepo.test.ts`);
swap `SqlClient` for a test layer where the instinct is to mock.
