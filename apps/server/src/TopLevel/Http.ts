/**
 * @since 0.0.0
 */

import * as Api from "@replaceme/domain/Api"
import * as Effect from "effect/Effect"
import * as HttpApiBuilder from "effect/unstable/httpapi/HttpApiBuilder"

/**
 * `health` is declared `NoContent`, so the handler answers `void` and the builder encodes the 204.
 *
 * @since 0.0.0
 * @category layers
 */
export const HttpTopLevelLive = HttpApiBuilder.group(Api.Http, "topLevel", (handlers) =>
  handlers.handle("health", () => Effect.withSpan(Effect.void, "TopLevel.health")),
)
