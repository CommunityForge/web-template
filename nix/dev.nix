_: {
  perSystem =
    {
      config,
      pkgs,
      nodejs,
      pnpm,
      ...
    }:
    let
      local = import ./local.nix;

      # The whole local app -- database, API, screen -- on the fixed ports in `local.nix`.
      #
      # These ports belong to this project, and the launcher TAKES THEM BACK on every start: whatever
      # listens on APP_PORT or API_PORT is stopped, because both restart in seconds. Supabase is slow
      # to start, so this project's stack is REUSED when it is already up, and another project's is
      # stopped (its data volumes kept) to free the shared Supabase ports. One repo at a time is the
      # expectation.
      #
      # The screen comes up first so a caller waiting on APP_PORT is answered while Supabase may still
      # be pulling images. The API and the screen are children of this script: either one exiting
      # stops the other and the launcher, so a half-running app is never left behind. Supabase is
      # left running on exit ON PURPOSE -- it is the expensive piece to bring back.
      launcher = pkgs.writeShellApplication {
        name = "dev";
        runtimeInputs = [
          nodejs
          pnpm
          pkgs.supabase-cli
          pkgs.docker-client
          pkgs.lsof
          pkgs.git
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = ''
          root="$(git rev-parse --show-toplevel)"
          cd "$root"
          export APP_PORT="${local.APP_PORT}"
          ${local.serverEnv}

          # Every listener on the port gets SIGTERM, then SIGKILL if it outlives five seconds.
          reclaim() {
            local port="$1" pids
            pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN || true)"
            [ -n "$pids" ] || return 0
            echo "[dev] port $port is held; stopping what holds it"
            echo "$pids" | xargs kill 2>/dev/null || true
            for _ in $(seq 50); do
              lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null || return 0
              sleep 0.1
            done
            lsof -tiTCP:"$port" -sTCP:LISTEN | xargs -r kill -9 2>/dev/null || true
          }

          web=""
          api=""
          cleanup() {
            trap - EXIT
            [ -z "$web" ] || kill "$web" 2>/dev/null || true
            [ -z "$api" ] || kill "$api" 2>/dev/null || true
            reclaim "$APP_PORT"
            reclaim "$API_PORT"
          }
          trap cleanup EXIT
          trap 'exit 143' TERM INT HUP

          if ! docker info >/dev/null 2>&1; then
            echo "[dev] Docker is not running. Start Docker Desktop, then start the app again." >&2
            exit 1
          fi

          pnpm install

          reclaim "$APP_PORT"
          reclaim "$API_PORT"

          (cd apps/frontend && exec ./node_modules/.bin/vite) \
            > >(sed -u 's/^/[web] /') 2>&1 &
          web=$!

          project="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' supabase/config.toml)"
          docker ps --filter label=com.supabase.cli.project \
            --format '{{.Label "com.supabase.cli.project"}}' \
            | sort -u \
            | { grep -vxF "$project" || true; } \
            | while read -r other; do
                echo "[dev] stopping the local Supabase of another project: $other"
                supabase stop --project-id "$other" 2>&1 | sed -u 's/^/[db] /'
              done
          supabase start 2>&1 | sed -u 's/^/[db] /'
          ${config.apps.db-migrate.program} 2>&1 | sed -u 's/^/[db] /'

          (cd apps/server && exec "$root/node_modules/.bin/tsx" watch src/main.ts) \
            > >(sed -u 's/^/[api] /') 2>&1 &
          api=$!

          wait -n "$web" "$api"
        '';
      };
    in
    {
      apps.dev = {
        type = "app";
        meta.description = "Run the whole app locally: Supabase, the API and the screen, on fixed ports";
        program = launcher;
      };
      # Built by `nix flake check` so shellcheck reads the launcher in CI.
      checks.dev = launcher;
    };
}
