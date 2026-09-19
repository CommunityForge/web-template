# TODO

## Tooling

### Choice Frameworks & Software

- [x] Serverless [React][react] SPA scaffold (not best-in-class but viable)
- [ ] [Supabase][supabase] for any shared persistence
- [x] [Shadcn][shadcn] component library
- [x] [Lucide][lucide] icon library
- [x] [TailwindCSS][tailwindcss] v4 styling
- [x] [Effect][effect] state management, side-effect handling, reactivity via Atom

### Determinism & Safety

- [x] [Nix flakes][nix-flakes] for deterministic builds and verifiable, agnostic environments
- [x] [PNPM][pnpm] FOD hashing with custom solution
- [x] Local `./claude` directory for denying writes above repo root _(partial)_

### Feedback

- [x] Type checking (`tsgo`)
- [x] Unit testing ([Vitest][vitest])
- [x] Integration testing (Vitest)
- [x] Formatting ([`oxc`][oxc] with [`treefmt-nix`][treefmt-nix] wrapper)
- [x] Type-aware linting (`oxc`)
- [x] GHA linting (`actionlint`)

### Harnessing & Context

- [x] Skills & MCP
  - [x] Official `effect-ts` skill
  - [x] Custom `effect-atom-react` skill with `Effect-TS/website` as prior art
  - [x] `supabase` _(**TODO:** consider if necessary per project)_
  - [ ] Shadcn MCP **(?)** is a skill for now
- [x] [OpenSpec][openspec] for tracking delta across product-based specifications
- [ ] E2E harnessing with LLM-run browser support; consider responsive layout and screenshotting automation
- [x] Install hooks for static analysis checks; needs testing

## Design Solutioning

- Figma or some such for prototyping design?

## User Experience

- [x] Interface for lay usage; likely Claude Desktop

## Security

- [x] Custom sandboxing is too rigid; fell back to Claude's built-in sandbox (`nono` removed)
- [ ] How to handle regular CVEs and dependency upgrades?

## Deployment

- [x] GitHub Actions
  - [x] Flake checks
- [ ] Choose between staging and blue/green for human-in-the-loop testing
- [x] Static SPA export for agnostic hosting
- [x] Server hosting: the API runs in the same Cloudflare Worker as the SPA, Postgres via Hyperdrive

## Late Game

- [ ] Capture token usage metrics for feature building and compare against industry standard

[effect]: https://effect.website
[lucide]: https://lucide.dev/
[nix-flakes]: https://determinate.systems/blog/nix-flakes-explained/
[openspec]: https://openspec.dev/
[oxc]: https://oxc.rs/
[pnpm]: https://pnpm.io/
[react]: https://react.dev/
[shadcn]: https://ui.shadcn.com/
[supabase]: https://supabase.com/
[tailwindcss]: https://tailwindcss.com/
[treefmt-nix]: https://github.com/numtide/treefmt-nix
[vitest]: https://vitest.dev/
