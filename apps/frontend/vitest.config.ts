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
  },
}

export default mergeConfig(shared, config)
