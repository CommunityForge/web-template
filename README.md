# Community Forge Web Template

> [!WARNING]
> This project is a work-in-progress.
> Breaking changes will be frequent.
> Public-facing documentation, including installation instructions, is incomplete.

A minimal, app-agnostic pnpm + TypeScript + Effect monorepo with reproducible Nix builds.
Structure follows [Effect](https://github.com/Effect-TS/effect)'s conventions; the Nix layer
follows SolidChess's. Everything domain-specific has been stripped — `packages/core` is a
placeholder to be deleted once real modules land, and `apps/frontend` is a Vite + React 19 + Tailwind 4
SPA shell.

The npm scope is the literal placeholder `@replaceme`. Renaming on fork takes two steps.

First the scope (`sed -i ''` is BSD/macOS; on GNU sed drop the `''`):

```sh
grep -rl '@replaceme' --exclude-dir={node_modules,.git,.direnv,dist,.repos} . \
  | xargs sed -i '' 's|@replaceme|@yourscope|g'
```

Then `projectName` in `flake.nix`, which names the `toolchain` and `devShell` derivations.
A bare `replaceme` search-and-replace will not do: it also matches inside the word
"replacement", which appears in several vendored skill documents.

## Getting a shell

Every command assumes the Nix dev shell, which supplies Node, pnpm, oxlint, oxfmt, tsgolint and
typos — there is no `packageManager` field and no `.nvmrc`.

The only host prerequisite is Nix itself, installed with a daemon — the tracked sandbox config in
`.claude/settings.json` talks to the daemon socket. The
[Determinate Systems installer](https://determinate.systems/install/) is the
recommended path: flakes enabled out of the box, and a clean uninstall. Any other
multi-user install works too.
From there, install Nix, clone, and point Claude Code at the repo root; an agent bootstraps
through `nix develop -c` on its own.

### First-time setup (macOS)

Never used a terminal? You don't need one to start.

Joining a team project that already lives on GitHub? Three things happen in the browser
before your Mac needs anything:

1. Accept the repository invitation — it arrives by email and also waits at
   [github.com/notifications](https://github.com/notifications). No GitHub account yet?
   Create one at [github.com/signup](https://github.com/signup) first.
2. On the repository page, click the green **Code** button and choose **Download ZIP**,
   then unzip it somewhere like Documents.
3. Day to day, the team works in the [Claude desktop app](https://claude.com/download) —
   its **Code** tab (paid Claude plan required) is where you open the project folder and
   ask for changes in plain English. The setup wizard below walks you through installing
   it, so you can also leave this for later.

Then find the file called `Setup.command` in the project folder and double-click it. A
window opens and walks you through everything, one step at a time — it opens the right web
pages, tells you exactly what to click, and only ever touches this project folder and Nix's
own settings; it never sends anything to GitHub for you. It ends
by connecting the folder to the team's GitHub repository, including the one-time GitHub
sign-in that lets you share your work. You can close it at any point and double-click it
again later; it skips whatever is already done. If macOS says the file can't be opened or
may be malware, click **Done** (not Move to Trash), open **System Settings → Privacy &
Security**, scroll to the bottom, and click **Open Anyway** next to the message about
`Setup.command`; confirm once and it opens normally from then on.

### First-time setup (Windows)

The same three browser steps above apply. Then find the file called `Setup.cmd` in the
project folder and double-click it. It walks you through the same stages as the Mac wizard,
with two Windows-specific moments to expect:

- Windows asks for permission once to turn on its built-in Linux layer (WSL), and may ask
  for a restart — after restarting, double-click `Setup.cmd` again and it picks up where it
  left off.
- The wizard moves the project into Ubuntu's own disk, where it runs many times faster.
  From then on the Ubuntu copy is the project: open it from the Claude app's Code tab by
  picking the **Ubuntu (WSL)** environment, and find it in File Explorer under **Linux →
  Ubuntu → home**. The folder you unzipped on Windows becomes just the wizard's launcher.

If Windows SmartScreen says it protected your PC, click **More info**, then **Run anyway** —
the same one-time confirmation as on the Mac. Setup for Linux will ship as a separate
wizard.

Or do the bootstrap by hand:

```sh
git submodule update --init --recursive # reference checkouts under .repos/, for agents
nix develop -c pnpm install
```

`.repos/` holds shallow read-only checkouts that coding agents consult as prior art. Nothing
in the build depends on them; skip the submodule step if you do not need them.

| Command            | What it does                                      |
| ------------------ | ------------------------------------------------- |
| `pnpm check`       | Type-checks the whole graph, sources and tests    |
| `pnpm test`        | Vitest across all workspace units                 |
| `pnpm lint`        | oxlint                                            |
| `pnpm build`       | Builds every unit's `dist/`                       |
| `nix fmt`          | treefmt — nix, shell, TS/JS, Markdown, YAML, JSON |
| `nix flake check`  | Formatting and spellcheck                         |
| `nix build .#core` | Reproducible build of one unit                    |

## Where the details live

`AGENTS.md` is the reference for how this repo is put together — layout, the conventions that are
load-bearing, adding a package or an app, the Nix build model, and the Effect wiring. It is written
for both humans and coding agents; read it before changing anything structural.

`apps/frontend/AGENTS.md` covers that app specifically.

## License

Not yet chosen. Until a `LICENSE` file lands, no rights are granted — the code is readable
here but not licensed for reuse, and `packages/core` is marked `private` so it cannot be
published by accident.
