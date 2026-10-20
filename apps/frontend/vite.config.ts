import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import * as path from "node:path"
import { defineConfig } from "vite"

// `import.meta.dirname` rather than `__dirname`: Vite's forthcoming native config loader
// does not support CJS globals.
const here = import.meta.dirname

// The dev server's ports are the launcher's to name. An unset one stops Vite here, and
// `strictPort` stops it when the port is taken, rather than drifting to the next free one.
const launcherPort = (name: string): number => {
  const value = process.env[name]
  if (value === undefined || value === "") {
    throw new Error(`${name} is unset. Start the app with \`nix run .#dev\`.`)
  }
  return Number(value)
}

export default defineConfig(({ command, isPreview }) => ({
  plugins: [react(), tailwindcss()],
  resolve: {
    // Mirrors `compilerOptions.paths` in `tsconfig.app.json`. tsc only type-checks; the bundler
    // resolves independently, so the alias has to be declared in both places.
    alias: {
      "@": path.join(here, "src"),
    },
  },
  // `/api` on the screen's own origin, as the Worker serves it in production.
  ...(command === "serve" && isPreview !== true
    ? {
        server: {
          port: launcherPort("APP_PORT"),
          strictPort: true,
          proxy: { "/api": { target: `http://127.0.0.1:${launcherPort("API_PORT")}` } },
        },
      }
    : {}),
}))
