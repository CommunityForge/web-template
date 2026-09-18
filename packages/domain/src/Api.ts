import * as HttpApi from "effect/unstable/httpapi/HttpApi"
import * as OpenApi from "effect/unstable/httpapi/OpenApi"

import { TopLevelApi } from "./TopLevel/Api.js"

export const Http = HttpApi.make("api")
  //
  .add(TopLevelApi)
  .annotate(OpenApi.Title, "Replaceme API")
