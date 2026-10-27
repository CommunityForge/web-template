_: {
  perSystem =
    {
      config,
      pkgs,
      nodejs,
      pnpm,
      supabase-cli,
      ...
    }:
    let
      local = import ./local.nix;

      # The whole local app -- database, API, screen -- for THIS checkout, on this checkout's ports
      # (`local.nix`). Other checkouts' apps are never touched: several run side by side.
      #
      # A restart stops only this checkout's previous run: the pids it recorded in `.dev-app.pids`,
      # and whatever still listens on this checkout's ports from inside this checkout. A process
      # outside the checkout is never stopped, so a port held by another project is a refused start
      # naming the port.
      #
      # The database is this checkout's Supabase stack on the NATIVE runtime: every service a host
      # process, no Docker. The runtime is named explicitly so a running Docker is never picked
      # instead. On a host the native runtime does not support the launcher stops and says so.
      #
      # The screen comes up first so a caller waiting on APP_PORT is answered while the stack may
      # still be downloading. The API and the screen are children of this script: either one exiting
      # stops the other and the launcher, so a half-running app is never left behind. The stack is
      # left running on exit ON PURPOSE: its idle services stop themselves.
      launcher = pkgs.writeShellApplication {
        name = "dev";
        runtimeInputs = [
          nodejs
          pnpm
          supabase-cli
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
          ${local.appPorts}
          pids_file="$root/.dev-app.pids"

          # True when the process is running with its working directory inside this checkout.
          ours() {
            local cwd
            cwd="$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
            case "$cwd" in "$root" | "$root"/*) return 0 ;; *) return 1 ;; esac
          }

          alive() {
            local pid
            for pid in "$@"; do
              if kill -0 "$pid" 2>/dev/null; then return 0; fi
            done
            return 1
          }

          # SIGTERM to each of this checkout's pids, then SIGKILL to any that outlive five seconds.
          stop_ours() {
            local pids="" pid
            for pid in "$@"; do
              if [ "$pid" != "$$" ] && ours "$pid"; then pids="$pids $pid"; fi
            done
            [ -n "$pids" ] || return 0
            # shellcheck disable=SC2086 # one pid per word, on purpose
            kill $pids 2>/dev/null || true
            for _ in $(seq 50); do
              # shellcheck disable=SC2086
              alive $pids || return 0
              sleep 0.1
            done
            # shellcheck disable=SC2086
            kill -9 $pids 2>/dev/null || true
          }

          listeners() { lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true; }

          web=""
          api=""
          cleanup() {
            trap - EXIT
            # shellcheck disable=SC2046 # word splitting of the pid lists is the point
            stop_ours $web $api $(listeners "$APP_PORT") $(listeners "$API_PORT")
            rm -f "$pids_file"
          }
          trap cleanup EXIT
          trap 'exit 143' TERM INT HUP

          case "$(uname -s)" in
            Darwin)
              if [ "$(uname -m)" != arm64 ] || [ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
                echo "[dev] The local database needs a Mac with Apple silicon on macOS 14 or newer." >&2
                exit 1
              fi
              ;;
            Linux)
              if ! supabase --version >/dev/null 2>&1; then
                echo "[dev] The local database needs Linux with glibc 2.35 or newer (Ubuntu 22.04 or newer)." >&2
                exit 1
              fi
              ;;
          esac

          if [ -f "$pids_file" ]; then
            echo "[dev] stopping this checkout's previous run"
            # shellcheck disable=SC2046
            stop_ours $(cat "$pids_file")
          fi
          # shellcheck disable=SC2046
          stop_ours $(listeners "$APP_PORT") $(listeners "$API_PORT")
          echo "$$" >"$pids_file"

          pnpm install

          echo "[dev] screen on port $APP_PORT, API on port $API_PORT"
          (cd apps/frontend && exec ./node_modules/.bin/vite) \
            > >(sed -u 's/^/[web] /') 2>&1 &
          web=$!
          echo "$web" >>"$pids_file"

          echo "[db] starting this checkout's database (the first start downloads about 360 MB)"
          supabase start --runtime native 2>&1 | sed -u 's/^/[db] /'
          ${local.serverEnv}
          ${config.apps.db-migrate.program} 2>&1 | sed -u 's/^/[db] /'

          (cd apps/server && exec "$root/node_modules/.bin/tsx" watch src/main.ts) \
            > >(sed -u 's/^/[api] /') 2>&1 &
          api=$!
          echo "$api" >>"$pids_file"

          wait -n "$web" "$api"
        '';
      };
    in
    {
      apps.dev = {
        type = "app";
        meta.description = "Run the whole app locally: Supabase, the API and the screen, on this checkout's ports";
        program = launcher;
      };
      # Built by `nix flake check` so shellcheck reads the launcher in CI.
      checks.dev = launcher;
    };
}
