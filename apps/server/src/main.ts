import * as NodeRuntime from "@effect/platform-node/NodeRuntime"
import * as Layer from "effect/Layer"

import * as Node from "./Node.js"

Layer.launch(Node.HttpLive).pipe(NodeRuntime.runMain)
