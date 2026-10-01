# packages/supabase

Effect bindings for `supabase-js`, and nothing else. The package owns the _shape_ of a Supabase token and session;
what those claims mean is `@replaceme/domain`'s business, and `@replaceme/domain` is the only workspace dependency.

Load `supabase` before wrapping a new SDK call or designing anything over Auth, Storage or Realtime.

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

## Wrapping an SDK call

`supabase-js` _resolves_ on a failure and reports it in the result's `error` field. `SupabaseAuth` lifts that field into
the typed failure channel; a wrapper that only guards the promise reports every rejected password as a success.
Failures map on a documented code (`AuthError.code` for Auth), never on message text.

Storage and Realtime are enabled locally and have no binding yet. A binding for either is a new module here that follows
`SupabaseAuth`: whatever the SDK reports as a failure becomes a tagged failure, mapped on its documented code. Realtime
reports through channel status rather than a resolved `error`, so its lift sits at the subscription.

## Tests

`test/ScriptedAuthClient.ts` is the harness: an in-memory stand-in for the `supabase-js` client covering the `auth`
surface `SupabaseAuth` touches, driven by a `Script` of what each call resolves to. Extend the `Script` when a new SDK
call is wrapped; a mocking framework is not used. `test/session.test.ts` reaches `internal/session` by relative path.
