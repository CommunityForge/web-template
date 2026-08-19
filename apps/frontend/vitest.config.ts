import react from "@vitejs/plugin-react"
import * as path from "node:path"
import { mergeConfig, type ViteUserConfigExport } from "vitest/config"

import shared from "../../vitest.shared.js"

// A `vitest.config.ts` replaces `vite.config.ts` rather than merging with it, so the React
// plugin is restated here for JSX in `test/*.test.tsx`. Tailwind is not: no test renders
// against real stylesheets. The `@/*` alias has to be restated for the same reason -- without
// it a test importing `@/components/ui/button` fails to resolve.
//
// `mergeConfig` concatenates arrays, so the shared `include` (`test/**/*.test.ts`) survives
// alongside the `.tsx` glob added below rather than being replaced by it.
const config: ViteUserConfigExport = {
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.join(import.meta.dirname, "src"),
    },
  },
  test: {
    environment: "happy-dom",
    include: ["test/**/*.test.tsx"],
    // Node >= 25 defines a `globalThis.localStorage` accessor that yields `undefined` unless
    // `--localstorage-file` is passed. Vitest 4's `getWindowKeys` skips any window key that is
    // already `in global` unless it is on its own hardcoded list, and `localStorage` is not --
    // so happy-dom's own, working `Storage` never reaches the global and `window.localStorage`
    // is `undefined`. Dropping Node's global restores the pre-25 path: vitest copies happy-dom's,
    // which is per-`Window` and so stays fresh per test file.
    //
    // vitest-dev/vitest#10867, fixed by #10293 in Vitest 5 -- drop this on that upgrade. The flag
    // exists from Node 22.4.0 and is a no-op below 25, so it needs no version gate.
    execArgv: ["--no-experimental-webstorage"],
  },
}

export default mergeConfig(shared, config)
