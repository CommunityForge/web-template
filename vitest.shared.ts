import type { ViteUserConfig } from "vitest/config"

import * as path from "node:path"

// `import.meta.dirname` rather than `__dirname`: Vite's forthcoming native config loader
// does not support CJS globals.
const here = import.meta.dirname

const config: ViteUserConfig = {
  server: {
    watch: {
      ignored: ["**/.direnv/**", "**/.repos/**", "**/dist/**", "**/result/**"],
    },
  },
  test: {
    setupFiles: [path.join(here, "vitest.setup.ts")],
    sequence: {
      concurrent: true,
    },
    include: ["test/**/*.test.ts"],
    // `exclude` REPLACES the default list, so `**/node_modules/**` and `**/dist/**` must be
    // restated. Defense-in-depth: the per-project `include` above already scopes collection.
    exclude: ["**/node_modules/**", "**/dist/**", "**/coverage/**", "**/.direnv/**", "**/.repos/**", "**/result/**"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      reportsDirectory: "coverage",
      exclude: [
        "node_modules/",
        "dist/",
        "coverage/",
        "test/utils/",
        "**/*.d.ts",
        "**/*.config.*",
        "**/vitest.setup.*",
        "**/vitest.shared.*",
      ],
    },
  },
}

export default config
