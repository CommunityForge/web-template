/* `as never` here builds deliberately partial test doubles: the assertions exercise one field of a wide third-party
 * payload, and spelling the rest out would assert nothing while coupling the test to the vendor's shape. */
/* eslint-disable typescript/no-unsafe-type-assertion */
/**
 * A scripted, in-memory stand-in for the `supabase-js` client, covering only the `auth` surface `SupabaseAuth.layer`
 * touches.
 *
 * The regression these tests exist for is unreachable against a real client: supabase-js _resolves_ on an
 * authentication failure and reports it in `error`, so "wrong password" and "signed in" differ only by a field that the
 * adapter used to ignore. Driving that field directly is the only way to pin the distinction.
 *
 * A hand-written seam passed to the constructor, rather than a mocking framework.
 */

import type * as SupabaseJs from "@supabase/supabase-js"

import * as Layer from "effect/Layer"

import * as SupabaseClient from "../src/SupabaseClient.js"

/**
 * What each scripted call should resolve to. Every field is optional; an omitted one resolves to the success shape with
 * no session, which is what an unexercised path should look like.
 */
export interface Script {
  readonly getSession?: SupabaseJs.Session | null
  readonly signInWithPassword?: { readonly error: SupabaseJs.AuthError | null }
  readonly signUp?: {
    readonly error: SupabaseJs.AuthError | null
    readonly session?: SupabaseJs.Session | null
  }
  readonly signInWithOAuth?: { readonly error: SupabaseJs.AuthError | null }
  readonly signInAnonymously?: { readonly error: SupabaseJs.AuthError | null }
  readonly signOut?: { readonly error: SupabaseJs.AuthError | null }
  readonly resend?: { readonly error: SupabaseJs.AuthError | null }
  readonly resetPasswordForEmail?: { readonly error: SupabaseJs.AuthError | null }
  readonly updateUser?: { readonly error: SupabaseJs.AuthError | null }
}

/**
 * Records what the adapter asked the client to do, so a test can assert on the options it passed rather than only on
 * the value it returned.
 *
 * The redirect targets are recorded because they are the half of the email round trip that a unit test can still reach:
 * whether the link a person receives points at the landing route, and whether it says which round trip it was. Getting
 * that wrong is silent -- the email sends, and lands somewhere that ignores it.
 */
export interface Calls {
  readonly signOutScopes: Array<string | undefined>
  readonly signUpRedirects: Array<string | undefined>
  readonly resendRedirects: Array<string | undefined>
  readonly resetRedirects: Array<string | undefined>
  readonly updateUserAttributes: Array<SupabaseJs.UserAttributes>
}

/**
 * An `AuthError` as the server would report it. Only `code` is load-bearing for the mapping under test; the class
 * itself is not imported because the real constructor is not part of the contract being pinned.
 */
export const authError = (code: string, message = code): SupabaseJs.AuthError =>
  ({ code, message, name: "AuthApiError", status: 400 }) as unknown as SupabaseJs.AuthError

export const make = (
  script: Script = {},
): { readonly layer: Layer.Layer<SupabaseClient.SupabaseClient>; readonly calls: Calls } => {
  const calls: Calls = {
    signOutScopes: [],
    signUpRedirects: [],
    resendRedirects: [],
    resetRedirects: [],
    updateUserAttributes: [],
  }

  const client = {
    auth: {
      getSession: () => Promise.resolve({ data: { session: script.getSession ?? null }, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
      stopAutoRefresh: () => Promise.resolve(),
      signInWithPassword: () =>
        Promise.resolve({ data: { session: null, user: null }, error: script.signInWithPassword?.error ?? null }),
      signUp: (credentials?: { readonly options?: { readonly emailRedirectTo?: string } }) => {
        calls.signUpRedirects.push(credentials?.options?.emailRedirectTo)
        return Promise.resolve({
          data: { session: script.signUp?.session ?? null, user: null },
          error: script.signUp?.error ?? null,
        })
      },
      resend: (params?: { readonly options?: { readonly emailRedirectTo?: string } }) => {
        calls.resendRedirects.push(params?.options?.emailRedirectTo)
        return Promise.resolve({ data: { user: null, session: null }, error: script.resend?.error ?? null })
      },
      resetPasswordForEmail: (_email: string, options?: { readonly redirectTo?: string }) => {
        calls.resetRedirects.push(options?.redirectTo)
        return Promise.resolve({ data: {}, error: script.resetPasswordForEmail?.error ?? null })
      },
      updateUser: (attributes: SupabaseJs.UserAttributes) => {
        calls.updateUserAttributes.push(attributes)
        return Promise.resolve({ data: { user: null }, error: script.updateUser?.error ?? null })
      },
      signInWithOAuth: () =>
        Promise.resolve({ data: { provider: "github", url: null }, error: script.signInWithOAuth?.error ?? null }),
      signInAnonymously: () =>
        Promise.resolve({ data: { session: null, user: null }, error: script.signInAnonymously?.error ?? null }),
      signOut: (options?: { readonly scope?: string }) => {
        calls.signOutScopes.push(options?.scope)
        return Promise.resolve({ error: script.signOut?.error ?? null })
      },
    },
  }

  return {
    layer: Layer.succeed(SupabaseClient.SupabaseClient, {
      client: client as unknown as SupabaseJs.SupabaseClient,
      redirectTo: new URL("https://example.test/auth/callback"),
    }),
    calls,
  }
}
