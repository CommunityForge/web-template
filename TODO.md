# TODO

## Tooling

### Choice Frameworks & Software

- [x] Serverless React SPA scaffold
- [ ] Supabase for any shared persistence
- [x] Shadcn component library
- [x] Lucide icon library
- [x] TailwindCSS v4 styling
- [x] Effect state management, side-effect handling, reactivity via Atom

### Determinism & Safety

- [x] Nix for deterministic builds and verifiable, agnostic environments

### Feedback

- [x] Type checking
- [x] Unit testing
- [x] Integration testing
- [x] Formatting
- [x] Type-aware linting

### Harnessing & Context

- [x] Skills & MCP
  - [x] Official `effect-ts` skill
  - [x] Custom `effect-atom-react` skill with `Effect-TS/website` as prior art
  - [x] `supabase` _(**TODO:** consider if necessary per project)_
  - [ ] Shadcn MCP **(?)**
- [x] [OpenSpec][openspec] for tracking delta across product-based specifications
- [ ] [Superpowers][superpowers] for agentic workflow
- [ ] E2E harnessing with LLM-run browser support - consider responsive layout and screenshotting automation
- [ ] Install hooks for static analysis checks

## Design Solutioning

- Figma or some such for prototyping design?

## User Experience

- [ ] Interface for lay usage; likely Claude Desktop

## Security

- [x] Custom sandboxing is too rigid; fell back to Claude's built-in sandbox (`nono` removed)
- [ ] How to handle CVEs and dependency upgrades?

## Deployment

- [ ] GitHub Actions
- [ ] Choose between staging and blue/green for human-in-the-loop testing
- [x] Static SPA export for agnostic hosting

## Late Game

- [ ] Capture token usage metrics for feature building and compare against industry standard

## Open Questions

- How best to achieve OpenSpec + Superpowers combination?
  - https://github.com/Fission-AI/OpenSpec/pull/970

[openspec]: https://openspec.dev/
[superpowers]: https://github.com/obra/superpowers
