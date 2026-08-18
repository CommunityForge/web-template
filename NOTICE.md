# Third-party content

This repository vendors documentation authored by others. `skills-lock.json` is the
machine-readable record of where each bundle came from; this file is the human-readable one.
Licenses below were confirmed against the GitHub API, not assumed.

## Vendored under `.agents/skills/`

Copied into this tree and redistributed with it.

| Bundle              | Upstream                | License                       |
| ------------------- | ----------------------- | ----------------------------- |
| `shadcn`            | `shadcn-ui/ui`          | MIT                           |
| `supabase`          | `supabase/agent-skills` | MIT                           |
| `effect-ts`         | `Effect-TS/skills`      | **None declared** — see below |
| `effect-atom-react` | first-party             | this repository               |

`.agents/skills/shadcn/assets/*.png` are shadcn's marks and travel with that bundle.

**`Effect-TS/skills` publishes no LICENSE file.** The repository is public, but absent a
license no reuse rights are granted, so redistributing that bundle here rests on nothing more
than the upstream's evident intent for it to be consumed by agents. If that matters for your
fork, drop `.agents/skills/effect-ts/` and its `.claude/skills/effect-ts` symlink, or ask
upstream to declare a license. (`Effect-TS/effect` itself is MIT; the skills repo is separate.)

## Referenced under `.repos/`

Git submodules — pinned commits, not copies, and not redistributed by this repository.

| Path                      | Upstream                    |
| ------------------------- | --------------------------- |
| `.repos/effect-website`   | `Effect-TS/website`         |
| `.repos/openspec-schemas` | `JiangWay/openspec-schemas` |

Nothing in the build depends on `.repos/`; it exists as prior art for coding agents.
