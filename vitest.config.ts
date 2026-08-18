import { defineConfig } from "vitest/config"

// Root config contributes NO `include`/`setupFiles` of its own -- each project merges
// `vitest.shared.ts` itself. Without this file, a bare `vitest` at the repo root globs
// every `*.test.ts` on disk, including vendored checkouts under `.repos/`.
export default defineConfig({
  test: {
    projects: ["packages/*/vitest.config.ts", "apps/*/vitest.config.ts"],
  },
})
