import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import * as path from "node:path"
import { defineConfig } from "vite"

// `import.meta.dirname` rather than `__dirname`: Vite's forthcoming native config loader
// does not support CJS globals.
const here = import.meta.dirname

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    // Mirrors `compilerOptions.paths` in `tsconfig.app.json`. tsc only type-checks; the bundler
    // resolves independently, so the alias has to be declared in both places.
    alias: {
      "@": path.join(here, "src"),
    },
  },
})
