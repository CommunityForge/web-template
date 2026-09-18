import * as NodeRuntime from "@effect/platform-node/NodeRuntime"
import * as Layer from "effect/Layer"

import { HttpLive } from "./Http.js"

Layer.launch(HttpLive).pipe(NodeRuntime.runMain)
