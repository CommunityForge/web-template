import * as HttpApi from "effect/unstable/httpapi/HttpApi"
import * as OpenApi from "effect/unstable/httpapi/OpenApi"

import { TopLevelApi } from "./TopLevel/Api.js"

/**
 * Every route lives under `/api/*`. The prefix is part of the contract: a client and the server agree on it here, and a
 * deployment that serves the API beside a static site routes on it.
 *
 * @since 0.0.0
 * @category api
 */
export const Http = HttpApi.make("api")
  //
  .add(TopLevelApi)
  .prefix("/api")
  .annotate(OpenApi.Title, "Wilkinsburg Land Bank API")
