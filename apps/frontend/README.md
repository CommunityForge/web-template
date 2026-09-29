# frontend

A Vite + React 19 + Tailwind 4 single-page app.

## Commands

All of these assume the dev shell (`direnv allow`, or `nix develop -c <cmd>`).

| Command                                     | What it does                                    |
| ------------------------------------------- | ----------------------------------------------- |
| `pnpm --filter=@landbank/frontend dev`      | Vite dev server with HMR                        |
| `pnpm --filter=@landbank/frontend build`    | `tsc -b` then `vite build` → `dist/`            |
| `pnpm --filter=@landbank/frontend preview`  | Serve the built `dist/` locally                 |
| `pnpm --filter=@landbank/frontend check`    | Type-check only, no emit                        |
| `pnpm --filter=@landbank/frontend test`     | Vitest under happy-dom                          |
| `pnpm --filter=@landbank/frontend coverage` | Same, with v8 coverage                          |
| `pnpm --filter=@landbank/frontend lint`     | oxlint                                          |
| `nix build .#frontend`                      | Reproducible build; `$out` is the static bundle |

## Layout

```
index.html            Vite entry; loads src/main.tsx
src/main.tsx          createRoot + StrictMode + BrowserRouter
src/App.tsx           The <Routes> tree
src/routes/           One file per route, plus the layout route
src/index.css         @import "tailwindcss" and the design tokens
test/*.test.tsx       Vitest, happy-dom environment
vite.config.ts        React + Tailwind plugins, @/* alias
vitest.config.ts      Merges ../../vitest.shared.ts
frontend.nix          flake-parts module, imported by the root flake.nix
```
