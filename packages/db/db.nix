_: {
  perSystem =
    { pkgs, buildPnpmPackage, ... }:
    let
      fs = pkgs.lib.fileset;
      # `Pg.ts` deliberately has no `Config.withDefault`, so an unset variable stops the process
      # rather than silently connecting as `postgres`/`postgres`. That means the local values have to
      # be stated somewhere, and this is the somewhere -- matching `server.nix`.
      #
      # Local Supabase only. Production runs these against a real database with real credentials.
      dbEnv = ''
        export DB_HOST="''${DB_HOST:-127.0.0.1}"
        export DB_PORT="''${DB_PORT:-54322}"
        export DB_USER="''${DB_USER:-postgres}"
        export DB_PASSWD="''${DB_PASSWD:-postgres}"
        export DB_DATABASE="''${DB_DATABASE:-postgres}"
      '';
    in
    {
      packages.db = buildPnpmPackage {
        # Set to `pkgs.lib.fakeHash` when dependencies change; the failing build prints the
        # real hash to paste back in.
        hash = "sha256-copuGAh6IF/2H1lEKd0jv6VnXBhhm3avjSFXywMiSq0=";
        packageJsonPath = ./package.json;
        # The unit and its one workspace dependency: `tsc -b` builds the referenced project
        # first, so its sources have to be in the sandbox too.
        pnpmWorkspaces = [
          "@replaceme/db"
          "@replaceme/domain"
        ];
        # Explicit rather than bare directories: a bare directory sweeps node_modules/, dist/
        # and tsbuildinfo into the sandbox, and a stale dist/ would silently satisfy `tsc -b`
        # incrementality.
        extraSrcs = fs.unions [
          ./package.json
          ./tsconfig.json
          ./vitest.config.ts
          ./scripts
          ./src
          ./test
          ../domain/package.json
          ../domain/tsconfig.json
          ../domain/src
          # oxlint resolves its config -- and its `overrides.files` globs -- relative to the
          # config file's directory, so it has to sit at the source root.
          ../../.oxlintrc.json
        ];
        nativeBuildInputs = [ pkgs.oxlint ];
        doCheck = true;
        buildPhase = ''
          runHook preBuild
          pnpm --filter=@replaceme/db build
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          pnpm --filter=@replaceme/db check
          pnpm --filter=@replaceme/db test --run
          pnpm --filter=@replaceme/db test:types
          # `--disable-nested-config` stops oxlint discovering `.repos/effect/.oxlintrc.json`,
          # which declares a JS plugin that is not installed.
          oxlint --type-aware --disable-nested-config packages/db
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ./packages/db/dist ./packages/db/src ./packages/db/package.json $out/
          runHook postInstall
        '';
      };

      # No `runtimeInputs` on any app below, so they resolve `pnpm`/`node`/`supabase` from the dev
      # shell rather than pinning a second copy of each: fine inside `nix develop`, not
      # self-contained outside it.
      apps = {
        # Apply pending migrations to whatever `DB_*` points at (local Supabase unless overridden).
        #
        # `supabase db reset` recreates `auth.*` and wipes `public`, which takes the migrator's own
        # `effect_sql_migrations` ledger with it -- so a reset is always followed by this. That is the
        # cost of Effect owning the DDL instead of the Supabase CLI, and `db-reset` below is the pair
        # that makes it one command again.
        db-migrate = {
          type = "app";
          meta.description = "Apply pending database migrations";
          program = pkgs.writeShellApplication {
            name = "db-migrate";
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              ${dbEnv}
              pnpm exec tsx ./packages/db/src/bin/migrate.ts
            '';
          };
        };

        # The standing check behind `0001_data_api_lockdown`: fail if any table in an API-exposed
        # schema is reachable by `anon`/`authenticated` without row security. Separate from the
        # migration because the property is ongoing -- a table can arrive in the schema from any
        # author, long after any migration of ours has run -- and a one-time statement cannot assert
        # it.
        #
        # Cheap and read-only, so it is safe to run in CI and after every `db-migrate`.
        db-audit = {
          type = "app";
          meta.description = "Fail if any exposed table lacks row-level security";
          program = pkgs.writeShellApplication {
            name = "db-audit";
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              ${dbEnv}
              pnpm exec tsx ./packages/db/src/bin/audit.ts
            '';
          };
        };

        # The full local rebuild: drop everything, let Supabase recreate `auth.*`, then apply our
        # migrations on top. Ordering is load-bearing -- a user-owned table references `auth.users`,
        # so the migrations cannot run before GoTrue's own schema exists.
        #
        # `db-audit` runs last: a reset restores Supabase's stock default privileges, so the lockdown
        # has to be re-applied and re-checked rather than assumed.
        db-reset = {
          type = "app";
          meta.description = "Reset the local database and re-apply migrations";
          program = pkgs.writeShellApplication {
            name = "db-reset";
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              ${dbEnv}
              supabase db reset
              pnpm exec tsx ./packages/db/src/bin/migrate.ts
              pnpm exec tsx ./packages/db/src/bin/audit.ts
            '';
          };
        };

        # Regenerate the Supabase type description of the database. It is the oracle the row schemas
        # are checked against, so it is generated output -- regenerate it, never edit it.
        #
        # `supabase gen types` emits mutable properties; the script that follows marks them readonly,
        # which is why this is an app rather than a bare redirect.
        db-sync-supabase-local = {
          type = "app";
          meta.description = "Synchronize local Supabase DB types";
          program = pkgs.writeShellApplication {
            name = "db-sync-supabase-local";
            text = ''
              cd "$(git rev-parse --show-toplevel)/packages/db"
              supabase \
                gen \
                types \
                --lang='typescript' \
                --local \
                > './src/internal/supabase-database.ts'
              node ./scripts/fix-dogwater-supabase-types.ts
            '';
          };
        };
      };
    };
}
