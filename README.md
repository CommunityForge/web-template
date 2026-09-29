# Community Forge Web Template

> [!WARNING]
> This project is a work-in-progress.
> Breaking changes will be frequent.
> Public-facing documentation, including installation instructions, is incomplete.

A minimal, app-agnostic pnpm + TypeScript + Effect monorepo with reproducible Nix builds.
Structure follows [Effect](https://github.com/Effect-TS/effect)'s conventions. The units are a
contract package (`packages/domain`), a Postgres package with an audited, deny-by-default schema
(`packages/db`), Effect bindings for Supabase auth (`packages/supabase`), an HTTP API server that
implements the contract (`apps/server`), a Vite + React 19 + Tailwind 4 SPA shell
(`apps/frontend`), and `packages/lib`, the copy source for a new package.

## Renaming on fork

Every placeholder is one of four tokens. Substitute them in this order, over every tracked regular
file except `pnpm-lock.yaml`. Run the recipe from the dev shell (`direnv allow`, or
`nix develop`): its `sed` is GNU sed on every platform, which the bare `-i` and the `\b` in the slug
pass rely on. The file list keeps only regular files (mode `100…`) ON PURPOSE — `git ls-files` also
lists the symlinks under `.claude/skills` and the submodules under `.repos`, and one of those makes
`sed` abort the whole batch, leaving every file after it untouched:

| Token         | Is                                | Replace with     | Form                          |
| ------------- | --------------------------------- | ---------------- | ----------------------------- |
| `@replaceme`  | The npm scope                     | `@yourscope`     | literal                       |
| `replaceme`   | The slug: Nix names               | `yourslug`       | word-bounded: `\breplaceme\b` |
| `Replaceme`   | The display name: page title, API | `Your Name`      | literal                       |
| `example.org` | The production domain             | `yourdomain.tld` | literal                       |

The slug is word-bounded because "replacement" appears in vendored documents; a bare substitution
would rewrite it. The scope runs first so the slug pass does not see it.

```sh
files() { git ls-files -s | awk -F'\t' '$1 ~ /^100/ { print $2 }' | grep -v '^pnpm-lock.yaml$'; }
files | xargs sed -i 's|@replaceme|@yourscope|g'
files | xargs sed -i -E 's/\breplaceme\b/yourslug/g'
files | xargs sed -i 's|Replaceme|Your Name|g'
files | xargs sed -i 's|example\.org|yourdomain.tld|g'
pnpm install
```

Then set every unit's `hash` in its `<unit>/<name>.nix` back to `pkgs.lib.fakeHash`: the package name
feeds the fixed-output derivation, so every hash moves. `nix build .#<unit>` prints the real one to
paste back in.

## Deploying

Only GitHub deploys; nothing is ever published from a laptop. One Cloudflare Worker serves the site
and the API (`/api/*`) from one origin. A fork sets these once, under the repository's Settings →
Secrets and variables → Actions:

| Kind     | Name                       | Is                                                                                                                                |
| -------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Secret   | `CLOUDFLARE_API_TOKEN`     | A Cloudflare API token allowed to edit Workers                                                                                    |
| Secret   | `CLOUDFLARE_ACCOUNT_ID`    | The Cloudflare account the Worker lives in                                                                                        |
| Variable | `CLOUDFLARE_WORKER_NAME`   | Required. The existing Worker's name: the part of its `workers.dev` address before the first dot                                  |
| Variable | `PUBLIC_SUPABASE_URL`      | Required. The production Supabase project URL; the API verifies sign-in tokens against it                                         |
| Variable | `APP_ORIGINS`              | Required. Comma-separated origins allowed to call the API from another origin (the site itself needs none; the Vite dev URL does) |
| Variable | `LOG_LEVEL`                | Required. An Effect log level literal, case-sensitive: `Info` is the usual choice                                                 |
| Variable | `CLOUDFLARE_HYPERDRIVE_ID` | The Hyperdrive config the production Worker reaches Postgres through (below). Either this or the `DB_URL` secret                  |
| Secret   | `DB_URL`                   | Postgres connection string for production when there is no Hyperdrive yet: the Supabase session pooler, port 5432                 |
| Variable | `SUPABASE_PROJECT_REF`     | Required for previews. The production Supabase project's reference; pull-request previews look their branch up under it           |
| Secret   | `SUPABASE_ACCESS_TOKEN`    | Required for previews. A Supabase personal access token (Account → Access Tokens) that can read that project's branches           |
| Variable | `PRODUCTION_URL`           | Optional. The custom domain once there is one; until then the deployment badge links to the `workers.dev` address                 |

Every push to `main` deploys the site and API. Every pull request gets a preview link posted as a
comment; the preview serves both, pointed at the pull request's own Supabase branch and never at
production. That branch is the one Supabase's GitHub integration creates per git branch: under the
project's Settings → Integrations → GitHub, connect the repository with the **Working directory**
set to `supabase`, **Automatic branching** on, and **Supabase changes only** off, because every pull
request needs a branch. Enabling the integration turns Branching on, a paid feature billed per
branch-hour. The preview job waits for the integration's `Supabase Preview` check on the pull
request's latest commit, looks the branch up, applies this repository's own migrations to it (the
integration runs only `supabase/migrations`, and the schema lives in `packages/db`), then uploads
the Worker version. When `Supabase Preview` fails or is skipped, the integration's comment on the
pull request says why, and the preview job stops with a message pointing there. The integration
makes a Supabase branch when a git branch is created, so a git branch that predates it has none:
create one of the same name under the project's Branches page, then push a commit.

### Hyperdrive, once

Production reaches Postgres through a Cloudflare Hyperdrive (included on the Workers Free plan),
created once by hand with the Supabase project's **session pooler** connection string (port 5432,
never the transaction pooler on 6543):

```sh
wrangler hyperdrive create <name> --connection-string "postgres://postgres.<project>:<password>@<region>.pooler.supabase.com:5432/postgres?sslmode=require"
```

Store the printed id as the GitHub variable `CLOUDFLARE_HYPERDRIVE_ID`. Until it exists, the
`DB_URL` secret does the same job without the connection cache; once it exists, remove that secret
(`wrangler secret delete DB_URL`), because the Worker prefers the var to the binding.

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

| Command                     | What it does                                          |
| --------------------------- | ----------------------------------------------------- |
| `pnpm check`                | Type-checks the whole graph, sources and tests        |
| `pnpm test`                 | Vitest across all workspace units                     |
| `pnpm test:types`           | tstyche type tests, in every unit that has them       |
| `pnpm lint`                 | oxlint                                                |
| `pnpm build`                | Builds every unit's `dist/`                           |
| `nix fmt`                   | treefmt — nix, shell, TS/JS, Markdown, YAML, JSON     |
| `nix flake check`           | Formatting, spellcheck, and every unit's Nix build    |
| `nix build .#lib`           | Reproducible build of one unit                        |
| `nix build .#server-worker` | The deployable Worker directory: API bundle plus site |

## Where the details live

`AGENTS.md` is the reference for how this repo is put together — layout, the conventions that are
load-bearing, adding a package or an app, the Nix build model, and the Effect wiring. It is written
for both humans and coding agents; read it before changing anything structural.

Each unit has its own: `packages/domain/AGENTS.md`, `packages/db/AGENTS.md`,
`packages/supabase/AGENTS.md`, `apps/server/AGENTS.md`, `apps/frontend/AGENTS.md`.

## License

MIT. The full text is in `LICENSE` at the repo root and again in every unit's own root, so a
unit copied out on its own carries its license with it.
