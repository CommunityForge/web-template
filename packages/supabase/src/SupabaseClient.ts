/**
 * Wrapper for the Supabase client.
 *
 * ## Session storage is a layer, not a default
 *
 * supabase-js defaults to `localStorage`. That is a deployment decision — how long a stolen token stays useful, and
 * whether a session survives a tab close — so this module refuses to make it, and requires a `KeyValueStore` instead.
 * The composition root picks `BrowserKeyValueStore.layerLocalStorage`, `layerSessionStorage`, `layerIndexedDb`, or
 * `KeyValueStore.layerMemory` in tests, and nothing here changes.
 *
 * Note for the composition root: `KeyValueStore` is one tag, and an application that also stores its own state through
 * it will otherwise share this backing. Provide it _locally_ to this layer, on the layer's own `Layer.provide`, never
 * at the root.
 *
 * ## Neither `localStorage` nor `sessionStorage` mitigates XSS
 *
 * Both are readable by any script on the origin. `sessionStorage` shortens the window and drops cross-tab session
 * sharing; it does not make a stolen token harder to steal. The controls that do are a CSP and a short token lifetime.
 *
 * @since 0.0.0
 */

import type * as SupabaseJs from "@supabase/supabase-js"
import type * as Scope from "effect/Scope"

import * as Auth from "@landbank/domain/Auth"
import { createClient } from "@supabase/supabase-js"
import * as Config from "effect/Config"
import * as Context from "effect/Context"
import * as Effect from "effect/Effect"
import { pipe } from "effect/Function"
import * as Layer from "effect/Layer"
import * as Option from "effect/Option"
import * as Redacted from "effect/Redacted"
import * as Schema from "effect/Schema"
import * as KeyValueStore from "effect/unstable/persistence/KeyValueStore"

/**
 * Configuration for the Supabase client.
 *
 * @since 0.0.0
 * @category models
 */
export const SupabaseClientConfig = Schema.Struct({
  /**
   * The project URL, e.g. `https://<ref>.supabase.co`.
   */
  url: Schema.Union([Schema.URL, Schema.URLFromString]),

  /**
   * The anon/publishable key. It ships in browser bundles by design — the `Redacted` wrapper only guards against
   * accidental logging.
   */
  anonKey: Schema.Redacted(Schema.String),

  /**
   * Where the auth server sends the browser back to after an OAuth round-trip.
   *
   * Stated rather than read off `location.href`, because the value is what the caller asks Supabase to redirect to: it
   * should be a URL the project's allow-list names exactly, not whichever page the user happened to start from with
   * whatever query and fragment it carried.
   */
  redirectTo: Schema.Union([Schema.URL, Schema.URLFromString]),
})

/**
 * @since 0.0.0
 * @category models
 */
export type SupabaseClientConfig = typeof SupabaseClientConfig.Type

/**
 * The wrapped client, plus the configuration the auth adapter needs at call time.
 *
 * This is the package's own type rather than a re-export of `SupabaseJs.SupabaseClient`, so that configuration the SDK
 * has no slot for — `redirectTo` — travels with the client instead of being threaded through every caller.
 *
 * @since 0.0.0
 * @category models
 */
export interface SupabaseClientService {
  readonly client: SupabaseJs.SupabaseClient
  readonly redirectTo: URL
}

/**
 * @since 0.0.0
 * @category services
 */
export class SupabaseClient extends Context.Service<SupabaseClient, SupabaseClientService>()(
  "@landbank/supabase/SupabaseClient",
) {}

/**
 * Adapts a `KeyValueStore` to the storage interface supabase-js expects.
 *
 * `SupportedStorage` permits promise-returning methods, which is what lets an arbitrary `KeyValueStore` — including
 * genuinely asynchronous ones like IndexedDB — back the session. Failures become defects: a storage layer that cannot
 * answer is not a condition the auth flow can meaningfully recover from.
 */
const toSupportedStorage = (kv: KeyValueStore.KeyValueStore): SupabaseJs.SupportedStorage => ({
  getItem: (key) =>
    Effect.runPromise(
      Effect.orDie(Effect.map(kv.get(key), (value) => Option.getOrNull(Option.fromUndefinedOr(value)))),
    ),
  setItem: (key, value) => Effect.runPromise(Effect.orDie(kv.set(key, value))),
  removeItem: (key) => Effect.runPromise(Effect.orDie(kv.remove(key))),
})

/**
 * @since 0.0.0
 * @category constructors
 */
export const make = (
  options: typeof SupabaseClientConfig.Encoded,
): Effect.Effect<SupabaseClientService, Auth.AuthError, Scope.Scope | KeyValueStore.KeyValueStore> =>
  Effect.gen(function* () {
    const config = yield* pipe(
      options,
      Schema.decodeEffect(SupabaseClientConfig),
      Effect.mapError(
        (cause) =>
          new Auth.AuthError({
            message: "invalid SupabaseClient configuration",
            cause,
          }),
      ),
    )

    const kv = yield* KeyValueStore.KeyValueStore

    const client = yield* Effect.try({
      try: () =>
        createClient(config.url.toString(), Redacted.value(config.anonKey), {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
            flowType: "pkce",
            storage: toSupportedStorage(kv),
          },
        }),
      catch: (cause) =>
        new Auth.AuthError({
          message: "could not initialize Supabase client",
          cause,
        }),
    })

    /**
     * `autoRefreshToken` owns timers; stop them when the layer's scope closes.
     */
    yield* Effect.addFinalizer(() => Effect.promise(() => client.auth.stopAutoRefresh()))

    return { client, redirectTo: config.redirectTo }
  })

/**
 * @since 0.0.0
 * @category layers
 */
export const layer = (
  config: typeof SupabaseClientConfig.Encoded,
): Layer.Layer<SupabaseClient, Auth.AuthError, KeyValueStore.KeyValueStore> =>
  Layer.effect(SupabaseClient, make(config))

/**
 * @since 0.0.0
 * @category layers
 */
export const layerConfig = (
  config: Config.Wrap<typeof SupabaseClientConfig.Encoded>,
): Layer.Layer<SupabaseClient, Auth.AuthError | Config.ConfigError, KeyValueStore.KeyValueStore> =>
  Layer.effect(SupabaseClient, Config.unwrap(config).pipe(Effect.flatMap(make)))
