# apps/server

The HTTP server: one Node process that implements the contract `@replaceme/domain` declares. It owns no wire shape, no
endpoint definition, no error class and no table. What it owns is the **composition root** (which layers meet at
startup, and in what order), one thin **feature service** per API group, and the **`TokenVerifier`** implementation
that turns a bearer token into a principal. Nothing here is exported for another package to import.

| Module                 | Owns                                                                          |
| ---------------------- | ----------------------------------------------------------------------------- |
| `main.ts`              | `Layer.launch(HttpLive)` under `NodeRuntime.runMain`                          |
| `Http.ts`              | `HttpLive`: server, router, CORS, logger, and `ApiLive` with every group      |
| `Auth.ts`              | `AuthLive`: the auth middleware over a Supabase-bound `TokenVerifier`         |
| `JwksTokenVerifier.ts` | `TokenVerifier` over a remote JWKS: issuer, audience, algorithms all required |
| `Sql.ts`               | Re-export of `@replaceme/db`'s `PgLive`, so every feature names one module    |
| `TopLevel/Http.ts`     | `/health`                                                                     |

## The composition root

```
HttpLive
  = HttpRouter.serve(ApiLive, { middleware: cors(APP_ORIGINS) })
    |> withLogAddress              -- logs the bound address, /docs and /openapi.json once
    |> Layer.provide(ServerLive)   -- NodeHttpServer on API_PORT
    |> Layer.provide(AuthLive)     -- AuthMiddleware.layer over TokenVerifierLive
    |> Layer.provide(LoggerLive)   -- MinimumLogLevel from LOG_LEVEL

ApiLive = HttpApiBuilder.layer(Api.Http)
    |> Layer.provide(<one GroupLive per group>)
    |> Layer.provide(HttpApiSwagger.layer(Api.Http))
```

**Coverage is type-checked.** `HttpApiBuilder.layer(Api.Http)` requires the handler service of every group in the
`HttpApi`; a group added to the contract and not provided in `ApiLive` is an unsatisfied requirement `tsc -b` reports.

### Layer placement

- **A layer is memoized by identity.** `Sql.PgLive` provided under several features' `Live` layers builds once, so one
  pool serves every read. Providing it in several places is the pattern.
- **Two clients can share one tag.** A second SQL client provides the generic `SqlClient` tag as well as its own; merged
  at the root it would shadow Postgres or be shadowed by it. Such a client is provided INSIDE the one group that
  consumes it, on the group layer's own `Layer.provide`, so the group degrades alone when its store is unreachable.

Everything request-independent and shared (server, logger, auth) sits at the root. Everything a single group needs (its
service, its repository, a store client no one else uses) sits on that group's layer.

### Config-shaped layers

A layer whose SHAPE depends on configuration is `Layer.unwrap` of an effect that reads the config and returns the
layer (`LoggerLive`, `HttpLive`). A layer whose VALUES come from configuration takes a `Config` in its options
(`NodeHttpServer.layerConfig(createServer, { port: Config.number("API_PORT") })`). Neither takes a plain argument. A
comma-separated variable is `Config.schema(Config.Array(Schema.String), "APP_ORIGINS")`: `Config.Array` is the schema
handed to `Config.schema`, not a `Config` constructor.

## Shape of a feature

A feature is two files and one line. `<Feature>.ts` is the service; `<Feature>/Http.ts` is the group; the line is
`Layer.provide(<Feature>Http.<Feature>GroupLive)` in `ApiLive`. The domain already holds the endpoint definitions,
the payload and success schemas, and the error classes; nothing here re-declares any of them.

**The service** is a `Context.Service` whose interface is written out (the surface the handlers program against), whose
`make` acquires its repositories, and whose `Live` provides them along with `Sql.PgLive`, so it is constructible from
nothing. Every method is `Effect.fn("<Service>.<method>")`; it annotates the identifying argument on the span, never a
payload body. The service owns the key derivation, the row-to-domain fold, and the request scope; the repository owns
the SQL. The first feature that reads a table adds `@replaceme/db` to its `Live` through `Sql.PgLive`.

**Error posture: infrastructure dies; only the contract's errors fail.** `SqlError` and `SchemaError` are not
something a client can act on, so a method whose whole error channel is infrastructure ends in `Effect.orDie`, and a
method that also fails with a domain error uses `Effect.catchTag(["SqlError", "SchemaError"], Effect.die)` so the
domain error survives. An endpoint's error channel is then exactly what its `HttpApiEndpoint` declared plus the
middleware's `Unauthorized`.

**Absence.** The service speaks `Option`; the handler is the one place that spells `None` as the endpoint's declared
`HttpApiError.NotFound`. A batch read never fails on a miss: a key the store has no rows for is absent from the
response, built with `Array.filterMap` over the requested keys so the answer is in request order.

**Authenticated features** keep `CurrentUser` in every method's `R` and read it themselves: it is REQUEST-scoped, so
it cannot be provided to `Live`, and keeping it in the signature makes "acts on behalf of a caller" a compile-time fact.
The service passes `userId` DOWN to the repository as an argument. The class docblock carries
`@effect-expect-leaking CurrentUser`, which tells the language service this leak is the design. A group is authenticated
or anonymous as a whole, decided in the domain's `.middleware(...)`, and the service mirrors it.

**The group** is `HttpApiBuilder.group(Api.Http, "<group>", (handlers) => ...)` with one `.handle` per endpoint,
each a one-liner forwarding to the service, `.pipe(Layer.provide(<Feature>.Live))`. Handlers perform no lookup,
derive no key and catch nothing.

Done when: `pnpm check` passes with the group provided; every service method has a span; the endpoint's runtime error
channel is only what the domain declared; an authenticated service reads `CurrentUser` in every method; `pnpm lint` is
clean; the feature's test swaps its repository for a stub layer.

## Authentication

Three modules, three responsibilities, one seam.

- **`TokenVerifier`** (domain) is the seam: `Redacted` credential in, `AuthPrincipal` out, `Unauthorized` on any
  failure.
- **`JwksTokenVerifier.ts`** is a mechanism: `jose`'s `jwtVerify` against `<issuer>/.well-known/jwks.json`, with
  `issuer`, `audience` and `algorithms` all REQUIRED options. Audience, because a provider mints other audiences for its
  own OAuth clients and none is this server. Algorithms, because `jose` otherwise accepts whatever the resolved key
  supports. Every failure is one opaque `Unauthorized`.
- **`Auth.ts`** is the binding: it reads `PUBLIC_SUPABASE_URL`, fixes issuer/audience/algorithms for Supabase, and
  supplies `decode: SupabaseClaims.toPrincipal(Schema.Unknown)`. That schema argument is the **entitlement seam**:
  `app_metadata` is the server-controlled claim, accepted undecoded until a feature gates on it, at which point the
  schema narrows there and the type flows into `CurrentUser.AuthPrincipal`.

Swapping providers replaces `Auth.ts` and possibly the mechanism module; the middleware, the services and the handlers
do not move. Whether an anonymous principal may use a route is decided against the principal's tag, never a role claim.

## Configuration

Every value comes from the ambient `ConfigProvider`, with no default anywhere in `src`. The launcher names each one:
`server-dev` in `server.nix` for development, the NixOS module in the same file for production.

| Variable              | Read by     | Meaning                                              |
| --------------------- | ----------- | ---------------------------------------------------- |
| `API_PORT`            | `Http.ts`   | HTTP listen port                                     |
| `LOG_LEVEL`           | `Http.ts`   | An Effect `LogLevel` literal, case-sensitive         |
| `APP_ORIGINS`         | `Http.ts`   | Comma-separated CORS allow-list; nothing else passes |
| `PUBLIC_SUPABASE_URL` | `Auth.ts`   | Provider base URL; issuer and JWKS derive from it    |
| `DB_*` (five)         | `db`'s `Pg` | Postgres, once a feature provides `Sql.PgLive`       |

CORS is pinned because authenticated endpoints take a bearer token: an unrestricted policy would let any page drive
them with a token it managed to read. Debug logging on a process that handles bearer tokens widens what a log
aggregator holds, so `LOG_LEVEL` is a deployment choice rather than a literal.

## Commands

`nix run .#server-dev` exports every variable above against local Supabase and runs the server in watch mode. The
startup log line names the bound address with `/docs` and `/openapi.json`, which is how a fresh checkout confirms the
Swagger layer is mounted. The root gate (`pnpm check`, `pnpm lint`, `pnpm test`) covers this app; `nix build .#server`
is the reproducible build and also proves the server → db → domain → supabase chain compiles.

## Tests

`test/TopLevel/Http.test.ts` is the model: the group's handler layer behind `HttpApiTest.groups(Api.Http,
["topLevel"])`, an in-memory typed client that runs the same encoding, routing and middleware as a real server with no
port bound. A feature test provides its `<Feature>GroupLive` with the repository swapped for a stub layer, and an
authenticated one adds `AuthMiddleware.layer` over a `Layer.succeed` `TokenVerifier` the way
`packages/domain/test/AuthMiddleware.test.ts` does. Test files mirror `src` file for file under `test/`.
