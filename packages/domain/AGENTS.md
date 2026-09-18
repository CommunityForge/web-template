# packages/domain

The contract layer: what a browser client and an HTTP server must agree on. Identity, wire shapes, endpoints, and the
errors that cross between them live here; what either program does with them does not. The package depends on
`effect` alone and ships no implementation of any seam it declares.

| Module           | Owns                                                                            |
| ---------------- | ------------------------------------------------------------------------------- |
| `Api`            | The root `HttpApi`: every feature group composed once                           |
| `TopLevel/Api`   | `/health`                                                                       |
| `Auth`           | Client-side auth vocabulary: address, credentials, session, errors, `Auth` seam |
| `AuthMiddleware` | Bearer middleware for the HttpApi: the server layer and the client layer        |
| `CurrentUser`    | The server-side, request-scoped principal (`Anonymous \| Member`)               |
| `TokenVerifier`  | The one seam that varies by auth mechanism: credential in, principal out        |
| `User`           | `UserId`, `User`, `Password`, `UserNotFound`                                    |

## Shape of a module

One module owns one data structure and the operations on it. A feature's HTTP group is a sibling file,
`<Feature>/Api.ts`, importing the vocabulary module rather than re-declaring a shape; `Api.ts` composes every group.

- **Wire shapes are `Schema.Class`, constructed with `.make`**, never a bare object literal for a named record. A
  field-level invariant sits on the field; a cross-field invariant is a `Schema.check` on the struct. A transport shape
  spreads the stored shape's `fields` rather than restating them, so two descriptions of one record cannot drift.
- **Ids are UUID-checked brands**: `Schema.String.pipe(Schema.check(Schema.isUUID()), Schema.brand("UserId"))`. They
  flow straight into SQL as row keys, and a non-UUID id did not come from the minting door. The check is provenance.
- **Sums, and the absences inside them.** A computed sum is a `Data.TaggedEnum` with constructors and matchers exported
  under the same name (`AuthPrincipal`), with a `WithGenerics` lambda when it is generic. A wire sum is a `Schema.Union`
  of named tagged members. "Unknown" is a member, never `null`. A missing member can be load-bearing (`SignUpRejected`
  has no `EmailInUse` reason on purpose); when an absence is the design, the docblock says so, because the next
  reader's instinct is to add it.
- **Errors map to HTTP at the declaration**, not in a handler: `{ httpApiStatus: 401 }` on `Unauthorized`, or
  `{ reason: HttpApiError.NotFound }`. One tag per REMEDY: `RateLimited` is distinct from `InvalidCredentials` because
  the fix is waiting rather than retyping; `LinkInvalid` covers expired and used links because the fix is the same. A
  provider detail that arrives only in prose is not parsed into a field.
- **Services are seams, not implementations.** The interface is a named export beside the tag, written out in full.
  `TokenVerifier`, `Auth` and `CurrentUser` are declared here and implemented elsewhere; the only layers this package
  ships are the two in `AuthMiddleware`, each written once against a seam. The request principal is provided per
  request by middleware (`Effect.provideService`), never by a layer, and annotated onto the span and log context by
  `userId` and `isAnonymous` only, never by address.

## Assembling an HTTP group

```ts
export class ThingApi extends HttpApiGroup.make("things")
  .add(HttpApiEndpoint.get("list", "/things", { success: Schema.Array(Thing) }))
  .add(
    HttpApiEndpoint.put("put", "/things/:id", {
      params: { id: ThingId },
      payload: Thing,
      success: HttpApiSchema.NoContent,
    }),
  )
  .annotate(OpenApi.Title, "Things")
  .middleware(AuthMiddleware.AuthMiddleware) {}
```

- Endpoint names are the handler keys a server implements, so renaming one is a server change.
- `.middleware(...)` binds only to endpoints already added, so it comes LAST.
- Authentication is a group-level decision, and the group's docblock records the reason in either direction: user data
  is authenticated; a shared, user-independent read is anonymous and the docblock names what a token would break.
- Numbers in query parameters arrive as strings: `Schema.FiniteFromString`. A replaced aggregate is an idempotent
  `PUT` of the whole value. A missing sub-resource is `HttpApiError.NotFound` on the wire; the client folds it back to
  `Option`.
- Then `.add(ThingApi)` in `Api.ts`. Done when the group is in `Api.Http`, its docblock states whether it is
  authenticated and why, and `pnpm check` passes for the package and the server that implements it (the server's
  `HttpApiBuilder.layer(Api.Http)` requires a handler layer for every group, so the unimplemented group is a type
  error there).

## Auth invariants

These are security properties of the error channel, and they bind whoever maps a provider's failures onto these tags.

- **The surfacing rule.** No operation returns a failure that distinguishes a registered address from an unregistered
  one: not a distinct tag, not a distinct message, not a present-versus-absent failure. A scripted attacker reads the
  response, not the page. `requestPasswordReset` and `resendConfirmation` succeed identically for both.
  `EmailNotConfirmed` is the ordinary SUCCESS shape of sign-up once confirmations are on and says nothing about prior
  registration. Timing is deliberately not claimed.
- **The principal is a tagged sum, not a flag.** `Anonymous` and `Member` share a role, so the role cannot be asked;
  the tag is the separator and `isAnonymous` is derived from it. Only `Member` holds an address, and it is
  `Option<string>` because a provider can authenticate without one; a present-but-blank address is lifted to `None` at
  the decode boundary, so `Some` always holds something usable.
- **Entitlements ride `appMetadata`**, the server-controlled claims, typed through the generic parameter and narrowed
  at the point a feature needs them. User-editable metadata is never consulted for an entitlement.
- **`Session` carries no token.** A token is an effect on the `Auth` service (`accessToken`) because the adapter may
  need to refresh before answering; a stored token field is a staleness bug waiting. Refresh tokens never leave the
  adapter.
- **Sign-up creates an identity; it never promotes the live one.** An anonymous session is a real identity that owns
  rows; linking it later preserves the id. The port carries no promotion operation.
- **Reset completion accepts no address.** It acts on whoever the recovery link signed in; accepting an address would
  invite a caller to believe it selects the account.
- **One weak-password refusal.** `setNewPassword` fails with `SignUpRejected({ reason: "WeakPassword" })`, so the
  sign-up form and the reset form cannot drift into saying different things.

## Consuming the contracts

**Server.** One `HttpApiBuilder.group(Api.Http, "<group>", (handlers) => ...)` per group with `.handle("<endpoint>",
...)` for each endpoint name, all provided to `HttpApiBuilder.layer(Api.Http)`. Authentication is
`AuthMiddleware.layer` provided with a `TokenVerifier` layer; an authenticated handler reads `CurrentUser.CurrentUser`
from context.

**Client.** `HttpApiClient.make(Api.Http, { baseUrl })`, typed `HttpApiClient.ForApi<typeof Api.Http>` and held as
ONE app service so every remote consumer shares a derivation. Authentication is `AuthMiddleware.layerClient` provided
with an `Auth` layer; the middleware attaches whatever credential is current, so identity flows as data and the adapter
is installed once with no branch on session.

## Tests

`test/User.test.ts` and `test/AuthMiddleware.test.ts` are the model. The first decodes and rejects through the schema
and asserts a failure with `Effect.flip`. The second builds the smallest authenticated API inside the test, swaps the
`TokenVerifier` seam for a `Layer.succeed` stub, and drives it through `HttpApiTest.groups`, an in-memory typed client
that runs the same encoding, routing and middleware as a real server without binding a port. The middleware is provided
TO the group layer with `Layer.provideMerge`, because the group resolves it while building its routes. Cases are
lowercase clauses with the subject elided: `rejects a string that is not a UUID`.
