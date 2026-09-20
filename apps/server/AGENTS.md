# apps/server

The HTTP API that implements the contract `@replaceme/domain` declares, and the Cloudflare Worker that serves it
beside the SPA. It owns no wire shape, no endpoint definition, no error class and no table. What it owns is the
**composition root** (which layers meet at startup, and in what order), one thin **feature service** per API group,
the **`TokenVerifier`** implementation that turns a bearer token into a principal, and the **Worker** that is the
production deployment. Nothing here is exported for another package to import.

| Module                 | Owns                                                                                    |
| ---------------------- | --------------------------------------------------------------------------------------- |
| `Http.ts`              | The portable root: `ApiLive` with every group and `CorsLive`, and `LoggerLive`          |
| `Node.ts`              | `HttpLive`: the portable root bound to a `NodeHttpServer` on `API_PORT`                 |
| `main.ts`              | `Layer.launch(Node.HttpLive)` under `NodeRuntime.runMain`                               |
| `Worker.ts`            | `SqlRequestLive`, `configProvider(env)`, `AppLive(env)`, and `export default { fetch }` |
| `Auth.ts`              | `AuthLive`: the auth middleware over a Supabase-bound `TokenVerifier`                   |
| `JwksTokenVerifier.ts` | `TokenVerifier` over a remote JWKS: issuer, audience, algorithms all required           |
| `Sql.ts`               | Re-export of `@replaceme/db`'s `PgLive` and `PgUrlLive`, so every feature names one     |
| `TopLevel/Http.ts`     | `/api/health`                                                                           |

## Two entry points over one portable core

`Http.ts` and everything under it (`Auth.ts`, `Sql.ts`, `TopLevel/`, the domain, the db package) touch no runtime:
no `node:*`, no `@effect/platform-node`. Node enters through exactly two modules, `Node.ts` and `main.ts`, and
Cloudflare through one, `Worker.ts`. The Worker bundle is built from `Worker.ts`, so a Node import anywhere under
`Http.ts` lands in that bundle and breaks it: keep runtime imports in the two modules that may have them.

`HttpRouter.serve(appLayer)` and `HttpRouter.toWebHandler(appLayer)` take the same app layer. That is the whole
trick: the two entry points differ in what they do with the router, not in what they route. Everything that wraps a
request (CORS, the request-scoped database) is a GLOBAL ROUTER MIDDLEWARE layer merged into the app layer, never the
`middleware` option of `serve` / `toWebHandler`: that option wraps the whole chain including the send, so a header
added there never reaches the client.

```
Node.HttpLive
  = HttpRouter.serve(Http.ApiLive)
    |> withLogAddress              -- logs the bound address, /api/docs and /api/openapi.json once
    |> Layer.provide(ServerLive)   -- NodeHttpServer on API_PORT; also HttpPlatform, Path, FileSystem, Etag
    |> Layer.provide(AuthLive)     -- AuthMiddleware.layer over TokenVerifierLive
    |> Layer.provide(LoggerLive)   -- MinimumLogLevel from LOG_LEVEL

Worker.make(env) = HttpRouter.toWebHandler(Worker.AppLive(env))

Worker.AppLive(env)
  = Layer.mergeAll(Http.ApiLive, SqlRequestLive)         -- SqlRequestLive: Sql.PgUrlLive per request, global
    |> Layer.provideMerge(HttpServer.layerServices)      -- pure-JS HttpPlatform, Path, Etag, no-op FileSystem
    |> Layer.provideMerge(AuthLive)
    |> Layer.provideMerge(LoggerLive)
    |> Layer.provideMerge(ConfigProvider.layer(configProvider(env)))

Http.ApiLive
  = Layer.mergeAll(
      HttpApiBuilder.layer(Api.Http, { openapiPath: "/api/openapi.json" })
        |> Layer.provide(<one GroupLive per group>)
        |> Layer.provide(HttpApiSwagger.layer(Api.Http, { path: "/api/docs" })),
      CorsLive)                                          -- HttpRouter.middleware(cors(APP_ORIGINS), { global: true })
```

The Worker MERGES what the Node root merely provides. Request fibers in a web handler run under the app layer's
built context and nothing else, so a service that must be visible at request time (the log level, the config
provider, the auth middleware) has to be an OUTPUT of the app layer, not just an input to its build.

`HttpServer.layerServices` is tagged `@category testing` upstream. It is used in the Worker ON PURPOSE: it is the
same four services `NodeHttpServer` provides, in pure JavaScript, with a `FileSystem` that does nothing, and no route
here serves a file. The day one does, that route needs a real file layer and this note changes.

### The Worker's I/O rule, in Effect terms

Workers forbid using a socket opened in one request from another. That maps onto one rule: **the `SqlClient` layer is
REQUEST-scoped in the Worker**. `SqlRequestLive` is `HttpRouter.middleware<{ provides: SqlClient }>()` around
`Effect.provide(app, Sql.PgUrlLive, { local: true })`, global: the client is built fresh inside every request and
closed with it, and the layer is typed as PROVIDING `SqlClient`, so a route that requires one is satisfied by it.
`local: true` is load-bearing: without it `Effect.provide` consults a memo map and a second request could be handed
the first request's client. Everything else (auth, logger, handlers) is built once per isolate.

A feature therefore never provides `Sql.PgLive` or `Sql.PgUrlLive` to its own `Live` in a way that would memoize it in
the app layer. A feature's service requires `SqlClient` and leaves it required; the entry point decides how it is
provided (the Node root may memoize one pool, the Worker must not).

`PgClient.listen` is off-limits in the Worker: Hyperdrive does not carry `LISTEN`/`NOTIFY`, and a request-scoped
client has nothing to listen on past its request.

### `env` is a `ConfigProvider`

No layer takes `env`. `configProvider(env)` is `ConfigProvider.fromUnknown(env)` with a fallback provider behind it
that answers `DB_URL` from the `HYPERDRIVE` binding's `connectionString`, and `AppLive(env)` merges it in as the
ambient provider. The layers then read `PUBLIC_SUPABASE_URL`, `LOG_LEVEL`, `APP_ORIGINS` and `DB_URL` exactly as they
do under Node, and a missing one fails the first request with a `ConfigError` naming it: the Worker's form of the
"no defaults" rule. The fallback reads the binding by property access, not by walking `env`: the binding is a
platform object whose fields are not own keys.

`DB_URL` resolves var-first: the var when present, else the binding's `connectionString`. Var first is ON PURPOSE. A
preview version inherits the production config, Hyperdrive binding included, so the var is what points a preview at
a database of its own. With neither, every request fails with a `ConfigError` naming `DB_URL`.

The handler is created once per isolate, on the first `fetch`: `make` is memoized on the `env` object with
`Function.memoize`. `env` is fixed for an isolate's life, so the identity key is exact, and there is no module-level
`let`.

`export default { fetch }` is the one default export in this repo outside tstyche templates: it is the Workers module
contract, the same kind of tool exception the import-style rules already carve out.

**Coverage is type-checked.** `HttpApiBuilder.layer(Api.Http)` requires the handler service of every group in the
`HttpApi`; a group added to the contract and not provided in `ApiLive` is an unsatisfied requirement `tsc -b` reports.

### Layer placement

- **A layer is memoized by identity.** Under the Node root, `Sql.PgLive` provided under several features' `Live`
  layers builds once, so one pool serves every read. Under the Worker the SQL layer is request-scoped instead (above);
  a feature keeps `SqlClient` in its requirements and lets the entry point provide it.
- **Two clients can share one tag.** A second SQL client provides the generic `SqlClient` tag as well as its own; merged
  at the root it would shadow Postgres or be shadowed by it. Such a client is provided INSIDE the one group that
  consumes it, on the group layer's own `Layer.provide`, so the group degrades alone when its store is unreachable.

Everything request-independent and shared (server, logger, auth) sits at the root. Everything a single group needs (its
service, its repository, a store client no one else uses) sits on that group's layer.

### Config-shaped layers

A layer whose SHAPE depends on configuration is `Layer.unwrap` of an effect that reads the config and returns the
layer (`LoggerLive`, `HttpLive`). A layer whose VALUES come from configuration takes a `Config` in its options
(`NodeHttpServer.layerConfig(createServer, { port: Config.Port("API_PORT") })`). Neither takes a plain argument. A
comma-separated variable is `Config.Array(Schema.String, "APP_ORIGINS")`: `Config.Array` is a `Config` constructor
taking the item schema and the path, and the older `Config.schema(Config.Array(...))` form no longer type-checks.

## Shape of a feature

A feature is two files and one line. `<Feature>.ts` is the service; `<Feature>/Http.ts` is the group; the line is
`Layer.provide(<Feature>Http.<Feature>GroupLive)` in `ApiLive`. The domain already holds the endpoint definitions,
the payload and success schemas, and the error classes; nothing here re-declares any of them.

**The service** is a `Context.Service` whose interface is written out (the surface the handlers program against), whose
`make` acquires its repositories, and whose `Live` provides them while leaving `SqlClient` required, so the entry point
decides how the database is provided. Every method is `Effect.fn("<Service>.<method>")`; it annotates the identifying
argument on the span, never a payload body. The service owns the key derivation, the row-to-domain fold, and the
request scope; the repository owns the SQL.

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
`server-dev` and `server-worker-dev` in `server.nix` for development, the GitHub workflows for the deployed Worker, the
NixOS module for a Node host. In the Worker the ambient provider is `configProvider(env)`, `ConfigProvider.fromUnknown`
over the bindings with the Hyperdrive fallback behind it; no layer takes `env` as an argument.

| Variable              | Read by     | Meaning                                                          |
| --------------------- | ----------- | ---------------------------------------------------------------- |
| `API_PORT`            | `Node.ts`   | HTTP listen port; Node only                                      |
| `LOG_LEVEL`           | `Http.ts`   | An Effect `LogLevel` literal, case-sensitive                     |
| `APP_ORIGINS`         | `Http.ts`   | Comma-separated CORS allow-list; nothing else passes             |
| `PUBLIC_SUPABASE_URL` | `Auth.ts`   | Provider base URL; issuer and JWKS derive from it                |
| `DB_*` (five)         | `db`'s `Pg` | Postgres for the Node root, once a feature needs `Sql.PgLive`    |
| `DB_URL`              | `db`'s `Pg` | Postgres for the Worker, one string; var-first over `HYPERDRIVE` |
| `HYPERDRIVE`          | `Worker.ts` | The Hyperdrive binding; its `connectionString` becomes `DB_URL`  |

CORS is pinned because authenticated endpoints take a bearer token: an unrestricted policy would let any page drive
them with a token it managed to read. In production the SPA and the API share one origin, so the policy only ever
admits the Vite dev origin. Debug logging on a process that handles bearer tokens widens what a log aggregator holds,
so `LOG_LEVEL` is a deployment choice rather than a literal.

## Cloudflare

One Worker serves the SPA's static assets and the API: one origin, one preview URL per pull request, no CORS between
them. `wrangler.json` beside this file is its config, and this unit owns it.

- **`wrangler.json` carries no `name` ON PURPOSE.** The workflows pass `--name` from the `CLOUDFLARE_WORKER_NAME`
  GitHub variable, so a fork never edits the file. It also carries no `vars`, no secrets and no Hyperdrive id: every
  account-specific value arrives from GitHub variables and secrets.
- **It is JSON, not JSONC,** so CI can extend it with `jq`. The composite action
  `.github/actions/wrangler-config` reads it and, when given a Hyperdrive id, writes `wrangler.generated.json`
  beside it with the `HYPERDRIVE` binding added; without an id the generated file is a plain copy and the Worker
  reads its `DB_URL` var instead, so a fresh fork deploys before it has created a Hyperdrive. The generated file is
  gitignored and sits in the same directory so the config's `./result/...` paths keep resolving.
- **`main` is `./result/worker.js` and `assets.directory` is `./result/assets`**, with `no_bundle: true`: the
  bundle is esbuild's, made by `pnpm run build:worker` into `build/worker.js` inside the Nix build, and wrangler
  uploads it as-is. `nix build .#server-worker` run from this directory leaves `./result` beside the config. The
  bundle lives in `build/`, not `dist/`: `tsc` emits `dist/Worker.js` from `src/Worker.ts`, and on a
  case-insensitive filesystem `dist/worker.js` would be the same file.
- **`run_worker_first: ["/api/*"]`** is why every route lives under `/api`: those paths reach the Worker, every other
  path is answered from the assets with the SPA's `index.html` as the not-found fallback, and the Worker's own 404
  is never seen for a page URL.
- **Node compatibility is on by the compatibility date** (`2026-09-01` is past the `2026-08-04` default-on date), so
  the bundle's `node:net`, `node:tls`, `node:crypto` and `node:buffer` imports resolve without a flag.
- **`packages.server-worker`** composes the deployable directory from `packages.server`'s `worker.js` and
  `packages.frontend`'s output. It is the ONE place this unit depends on the frontend, and it is Nix-only: pnpm never
  links the two, and the frontend stays a bundler leaf.

### Hyperdrive, and why its origin is the session pooler

Production binds one Hyperdrive; the preview workflow binds none, so a preview version's only database is the `DB_URL`
version secret it is uploaded with and there is no binding for it to fall through to. The one-time `wrangler hyperdrive
create` is in the README.

The Hyperdrive's origin is Supabase's **session pooler on port 5432**, not the direct connection. Supabase's direct
host is IPv6-only without the paid IPv4 add-on and Hyperdrive's IPv6 reach is undocumented; the session pooler is
IPv4, keeps prepared statements, and Hyperdrive's warm connections to it sit well inside its limits. Buying the IPv4
add-on and re-pointing the Hyperdrive at the direct host is a dashboard change with no code impact. Never the
transaction pooler on 6543: the client's prepared statements are named, and a transaction-mode pooler would answer a
later statement from a backend that never saw the `PREPARE`.

Hyperdrive requires TLS to the origin (`sslmode=require` in the connection string) and carries neither
`LISTEN`/`NOTIFY` nor SQL-level `PREPARE`; the client's protocol-level prepared statements are fine. Under
`wrangler dev` the local Hyperdrive leg hands out `sslmode=prefer`; the client tries TLS first and falls back, so
nothing special-cases it.

## Commands

`nix run .#server-dev` exports every variable above against local Supabase and runs the Node server in watch mode. The
startup log line names the bound address with `/api/docs` and `/api/openapi.json`, which is how a fresh checkout
confirms the Swagger layer is mounted. It is the primary development loop.

`nix run .#server-worker-dev` is the Worker shape: it builds `server-worker` for the assets, rebuilds `worker.js` on
every source change, and runs `wrangler dev` on it with `DB_URL` pointed at local Supabase (no Hyperdrive locally).
Use it to smoke-test what only the Worker runtime shows: `/` serving the SPA, `/api/health` reaching the handler,
`/nope` falling back to the SPA, and no "Cannot perform I/O" in the log across repeated requests.

The root gate (`pnpm check`, `pnpm lint`, `pnpm test`) covers this app. `nix build .#server` is the reproducible
build: it proves the server → db → domain → supabase chain compiles and emits `worker.js`; `nix build
.#server-worker` composes that bundle with the frontend into the directory `wrangler.json` deploys.

## Tests

`test/TopLevel/Http.test.ts` is the model: the group's handler layer behind `HttpApiTest.groups(Api.Http,
["topLevel"])`, an in-memory typed client that runs the same encoding, routing and middleware as a real server with no
port bound. A feature test provides its `<Feature>GroupLive` with the repository swapped for a stub layer, and an
authenticated one adds `AuthMiddleware.layer` over a `Layer.succeed` `TokenVerifier` the way
`packages/domain/test/AuthMiddleware.test.ts` does. Test files mirror `src` file for file under `test/`.

`test/Worker.test.ts` builds the web handler from a fake env record and drives it with plain `Request`s: `/api/health`,
`/api/docs`, `/api/openapi.json`, CORS against a two-origin allow-list, the `DB_URL`-over-`HYPERDRIVE` precedence
through `configProvider`, and a record missing `PUBLIC_SUPABASE_URL`, whose first request fails with a `ConfigError`.
No database is needed because no route queries one; the `DB_URL` in the fake env is never connected to.
