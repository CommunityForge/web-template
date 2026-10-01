{ self, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      buildPnpmPackage,
      ...
    }:
    let
      fs = pkgs.lib.fileset;
      PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
      # Comma-separated; `Http.ts` reads it through `Config.Array`. There is no default there -- an
      # unset value stops the server rather than silently allowing every origin. Both schemes,
      # matching `supabase/config.toml`'s `site_url` / `additional_redirect_urls` pair.
      APP_ORIGINS = "http://127.0.0.1:5173,https://127.0.0.1:5173,http://localhost:5173";
      # Local Supabase's Postgres. `Pg.ts` has no defaults either, so the launcher states them; the
      # server only reads them once a feature provides `Sql.PgLive`.
      DB_HOST = "127.0.0.1";
      DB_PORT = "54322";
      DB_USER = "postgres";
      DB_PASSWD = "postgres";
      DB_DATABASE = "postgres";
    in
    {
      packages.server = buildPnpmPackage {
        # Set to `pkgs.lib.fakeHash` when dependencies change; the failing build prints the
        # real hash to paste back in.
        hash = "sha256-E1cZNhwcmsmDMGtWuCCTkSsPqiEJnM73fpUTfpz+qbU=";
        packageJsonPath = ./package.json;
        # The app and its workspace dependency closure: `tsc -b` follows the app's `references`,
        # so every referenced project's sources have to be in the sandbox.
        pnpmWorkspaces = [
          "@replaceme/server"
          "@replaceme/db"
          "@replaceme/domain"
          "@replaceme/supabase"
        ];
        # Explicit rather than bare directories: a bare directory sweeps node_modules/, dist/
        # and tsbuildinfo into the sandbox, and a stale dist/ would silently satisfy `tsc -b`
        # incrementality.
        extraSrcs = fs.unions [
          ./package.json
          ./tsconfig.json
          ./vitest.config.ts
          ./src
          ./test
          ../../packages/db/package.json
          ../../packages/db/tsconfig.json
          ../../packages/db/src
          ../../packages/domain/package.json
          ../../packages/domain/tsconfig.json
          ../../packages/domain/src
          ../../packages/supabase/package.json
          ../../packages/supabase/tsconfig.json
          ../../packages/supabase/src
          # oxlint resolves its config -- and its `overrides.files` globs -- relative to the
          # config file's directory, so it has to sit at the source root.
          ../../.oxlintrc.json
        ];
        nativeBuildInputs = [ pkgs.oxlint ];
        doCheck = true;
        buildPhase = ''
          runHook preBuild
          pnpm --filter=@replaceme/server build
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          pnpm --filter=@replaceme/server check
          pnpm --filter=@replaceme/server test --run
          # `--disable-nested-config` stops oxlint discovering `.repos/effect/.oxlintrc.json`,
          # which declares a JS plugin that is not installed.
          oxlint --type-aware --disable-nested-config apps/server
          runHook postCheck
        '';
        # The compiled app, its sources and manifest -- the same shape the packages ship -- plus
        # `worker.js`, the Worker bundle `build` emits into `build/`. `dist/` is not a runnable
        # deployment: it ships without `node_modules`, and `pnpm deploy` (the shape that would run)
        # re-resolves against the registry, which the sandbox cannot reach. `worker.js` IS
        # runnable: one self-contained module importing only `node:*`, which is what
        # `server-worker` below composes into the deployable directory.
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ./apps/server/dist ./apps/server/src ./apps/server/package.json ./apps/server/build/worker.js $out/
          runHook postInstall
        '';
        doDist = false;
      };

      # The directory `wrangler.json` deploys: the API bundle beside the SPA's static assets, so one
      # Worker serves both from one origin. This is the ONE place the server unit depends on the
      # frontend, and it is Nix-only -- pnpm never links the two, so the frontend stays a bundler
      # leaf. `checks` picks this up with every other package.
      packages.server-worker = pkgs.runCommand "replaceme-server-worker" { } ''
        mkdir -p $out
        cp ${config.packages.server}/worker.js $out/worker.js
        cp -r ${config.packages.frontend} $out/assets
      '';

      apps = {
        server-dev = {
          type = "app";
          meta.description = "Run the server against local Supabase, restarting on source changes";
          program = pkgs.writeShellApplication {
            name = "server-dev";
            text = ''
              cd "$(git rev-parse --show-toplevel)/apps/server"
              export PUBLIC_SUPABASE_URL="${PUBLIC_SUPABASE_URL}"
              export DB_HOST="${DB_HOST}"
              export DB_PORT="${DB_PORT}"
              export DB_USER="${DB_USER}"
              export DB_PASSWD="${DB_PASSWD}"
              export DB_DATABASE="${DB_DATABASE}"
              export APP_ORIGINS="${APP_ORIGINS}"
              # `Http.ts` carries no Config defaults -- every launcher names its port and log level.
              export API_PORT="''${API_PORT:-3001}"
              export LOG_LEVEL="''${LOG_LEVEL:-Info}"
              pnpm install
              pnpm tsx watch src/main.ts
            '';
          };
        };
        # The Worker shape, locally: the bundle rebuilt on every source change, served by wrangler
        # beside the SPA from the last Nix build. `server-dev` stays the primary loop; this one is
        # for smoke-testing what only the Worker runtime shows (request-scoped I/O, asset routing).
        server-worker-dev = {
          type = "app";
          meta.description = "Run the Worker locally with wrangler, rebuilding the bundle on source changes";
          program = pkgs.writeShellApplication {
            name = "server-worker-dev";
            runtimeInputs = [ pkgs.wrangler ];
            text = ''
              root="$(git rev-parse --show-toplevel)"
              cd "$root/apps/server"
              pnpm install
              # `./result/assets` is what wrangler.json serves. The bundle beside it is the last
              # build's; the watcher below writes a fresh one to ./build/worker.js, which is the
              # script wrangler is told to run instead of the config's `main`.
              nix build "$root#server-worker" --out-link result
              pnpm run build:worker --watch &
              watcher=$!
              trap 'kill "$watcher"' EXIT
              # No Hyperdrive locally, so `DB_URL` is the whole database configuration: local
              # Supabase's Postgres, the same values `server-dev` exports one by one.
              wrangler dev ./build/worker.js \
                --config wrangler.json \
                --var "PUBLIC_SUPABASE_URL:${PUBLIC_SUPABASE_URL}" \
                --var "APP_ORIGINS:${APP_ORIGINS}" \
                --var "LOG_LEVEL:''${LOG_LEVEL:-Info}" \
                --var "DB_URL:postgres://${DB_USER}:${DB_PASSWD}@${DB_HOST}:${DB_PORT}/${DB_DATABASE}"
            '';
          };
        };
        server-check-watch = {
          type = "app";
          meta.description = "Type-check the server in watch mode";
          program = pkgs.writeShellApplication {
            name = "server-check-watch";
            text = ''
              cd "$(git rev-parse --show-toplevel)/apps/server"
              pnpm run check --watch
            '';
          };
        };
      };
    };

  # A systemd unit around `dist/main.js`, for a host that runs the Node entry point. It is NOT the
  # deploy path for Cloudflare: that is `packages.server-worker` plus `wrangler.json`, driven from
  # GitHub Actions.
  flake.nixosModules.server =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.services.server;
    in
    {
      options.services.server = {
        enable = lib.mkEnableOption "server service";
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.system}.server;
        };
        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        apiPort = lib.mkOption {
          type = lib.types.int;
          default = 3000;
        };
        # Exported as APP_ORIGINS, which the server reads as a comma-separated list to pin CORS. A
        # single origin is the common case, hence the singular option name; set several by
        # separating them with commas.
        appOrigin = lib.mkOption {
          type = lib.types.str;
          default = "https://example.org";
        };
        supabaseUrl = lib.mkOption {
          type = lib.types.str;
          description = "The Supabase project URL; the token issuer and JWKS endpoint derive from it";
        };
        # Effect's `LogLevel` literals verbatim: `Config.logLevel` parses these case-sensitively, and
        # the server carries no default to paper over a value it cannot parse.
        logLevel = lib.mkOption {
          type = lib.types.enum [
            "All"
            "Fatal"
            "Error"
            "Warn"
            "Info"
            "Debug"
            "Trace"
            "None"
          ];
          default = "Info";
          description = "LOG_LEVEL passed to the server";
        };
        noColor = lib.mkOption {
          type = lib.types.enum [
            "0"
            "1"
          ];
          default = "1";
          description = "NO_COLOR passed to the server";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = "server";
          description = "User account under which the server service runs";
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "server";
          description = "Group under which the server service runs";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.server =
          let
            server-systemd-script = pkgs.writeShellApplication {
              name = "server-systemd";
              # `cfg.package.nodejs` is the Node the package was built against, exposed by
              # `buildPnpmPackage`'s passthru -- one binding in `flake.nix` moves both.
              runtimeInputs = [
                pkgs.coreutils
                cfg.package.nodejs
                cfg.package
              ];
              text = ''
                node ${cfg.package}/dist/main.js
              '';
            };
          in
          {
            wantedBy = if cfg.autoStart then [ "multi-user.target" ] else [ ];
            description = "server";
            unitConfig = {
              StartLimitIntervalSec = lib.mkForce 0;
            };
            serviceConfig = {
              Type = "simple";
              User = cfg.user;
              Group = cfg.group;
              ExecStart = lib.getExe server-systemd-script;
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ProtectProc = "invisible";
              ProcSubset = "pid";
              # MemoryDenyWriteExecute is left off: Node's JIT needs writable executable pages.
              LockPersonality = true;
              CapabilityBoundingSet = [ ];
              AmbientCapabilities = [ ];
              UMask = "0077";
              RestrictNamespaces = true;
            };
            # Exactly what `src` reads. No defaults on the server side, so every variable is named.
            environment = {
              API_PORT = toString cfg.apiPort;
              APP_ORIGINS = cfg.appOrigin;
              PUBLIC_SUPABASE_URL = cfg.supabaseUrl;
              LOG_LEVEL = cfg.logLevel;
              NO_COLOR = cfg.noColor;
            };
          };
      };
    };
}
