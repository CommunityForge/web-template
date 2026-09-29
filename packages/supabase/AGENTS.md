# packages/supabase

Effect bindings for `supabase-js`, and nothing else. The package owns the _shape_ of a Supabase token and session;
what those claims mean is `@landbank/domain`'s business, and `@landbank/domain` is the only workspace dependency.

| Module           | Owns                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------- |
| `SupabaseClient` | The wrapped client as a service, plus the `redirectTo` the SDK has no slot for        |
| `SupabaseAuth`   | The domain's `Auth` service over that client: sign-in, sign-up, reset, anonymous, out |
| `SupabaseClaims` | The published access-token claim layout, decoded into the domain's `AuthPrincipal`    |
| `internal/*`     | The session decoder; blocked by the `exports` map, reached by tests through `../src/` |

## `KeyValueStore` is provided locally

`SupabaseClient.layer` requires a `KeyValueStore` for session persistence and refuses to default it: how long a stolen
token stays useful is a deployment decision. `KeyValueStore` is one tag, so an application that also stores its own
state through it would share the backing. Provide the store on the client layer's own `Layer.provide`, never at the
root.

## Which tokens become a principal

`SupabaseClaims.toPrincipal` accepts `role: "authenticated"` only. That role covers both permanent and anonymous users
(`is_anonymous` separates them), and excludes the publishable anon key and any `service_role` token. The
`app_metadata` schema is the caller's, because those are the only server-controlled claims; `user_metadata` is
user-editable and is not modeled at all. A decode failure is one opaque `Unauthorized`, so claim material never echoes
back to the caller.

`supabase-js` _resolves_ on an authentication failure and reports it in the result's `error` field. `SupabaseAuth`
lifts that field into the typed failure channel; a wrapper that only guards the promise reports every rejected password
as a success. Failures map on `AuthError.code`, a documented enum, never on message text.

## Tests

`test/ScriptedAuthClient.ts` is the harness: an in-memory stand-in for the `supabase-js` client covering the `auth`
surface `SupabaseAuth` touches, driven by a `Script` of what each call resolves to. Extend the `Script` when a new SDK
call is wrapped; a mocking framework is not used. `test/session.test.ts` reaches `internal/session` by relative path.
