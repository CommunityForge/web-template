# The local app's addresses: one place every development launcher reads them from.
#
# Nothing here is a fixed port. Each checkout runs its own whole app -- screen, API and database --
# so several checkouts can run side by side:
#
# - The screen and the API take ports DERIVED FROM THE CHECKOUT PATH, in 10000-19999: below the
#   20000-32767 range the Supabase stack allocates from, and below every OS's ephemeral range. Every
#   launcher derives the same pair, so `.#dev`, `.#server-dev` and `.#frontend-dev`'s `/api` proxy
#   agree without a state file. The screen takes the desktop panel's `PORT` instead when the panel
#   assigns one.
# - The database is this checkout's Supabase stack, whose ports the stack engine allocates and
#   remembers. Launchers read them from `supabase status --env` at start.
rec {
  # Local Supabase's Postgres credentials; the stack engine keeps Supabase's stock ones. `Pg.ts` has
  # no defaults, so the launchers state them.
  DB_USER = "postgres";
  DB_PASSWD = "postgres";
  DB_DATABASE = "postgres";

  # Exports APP_PORT and API_PORT. Needs `git` and `cksum` on PATH. Two checkouts landing on the same
  # slot (one chance in 5000) is a refused start naming the port, never a silent move.
  appPorts = ''
    app_slot="$(git rev-parse --show-toplevel | cksum | cut -d' ' -f1)"
    app_slot=$((app_slot % 5000))
    export APP_PORT="''${PORT:-$((10000 + 2 * app_slot))}"
    export API_PORT="$((10001 + 2 * app_slot))"
    unset app_slot
  '';

  # Exports PUBLIC_SUPABASE_URL, DB_URL and the five `DB_*` parts from this checkout's stack, each
  # only where the environment does not already name it. Stops the caller when the checkout has no
  # stack. Needs `supabase` on PATH.
  supabaseEnv = ''
    if ! supabase_status="$(supabase status --env 2>/dev/null)"; then
      echo "This checkout's local database is not running. Start the app first: nix run .#dev" >&2
      exit 1
    fi
    # The CLI quotes every value so that evaluating it performs no expansion; the subshell keeps
    # the other credentials it prints out of this environment.
    supabase_value() { (eval "$supabase_status" && printf '%s' "''${!1}"); }
    supabase_db_url="$(supabase_value DB_URL)"
    supabase_db_address="''${supabase_db_url#*@}"
    supabase_db_address="''${supabase_db_address%%/*}"
    export PUBLIC_SUPABASE_URL="''${PUBLIC_SUPABASE_URL:-$(supabase_value API_URL)}"
    export DB_URL="''${DB_URL:-$supabase_db_url}"
    export DB_HOST="''${DB_HOST:-''${supabase_db_address%:*}}"
    export DB_PORT="''${DB_PORT:-''${supabase_db_address##*:}}"
    export DB_USER="''${DB_USER:-${DB_USER}}"
    export DB_PASSWD="''${DB_PASSWD:-${DB_PASSWD}}"
    export DB_DATABASE="''${DB_DATABASE:-${DB_DATABASE}}"
    unset supabase_status supabase_db_url supabase_db_address
  '';

  # Everything the Node server reads, against this checkout's stack; runs after `appPorts`. `Http.ts`
  # carries no Config defaults, so every launcher names its origins and log level. APP_ORIGINS is
  # comma-separated (read through `Config.Array`, no default: an unset value stops the server rather
  # than allowing every origin), and lists both loopback names and both schemes the screen may be
  # opened on.
  serverEnv = ''
    ${supabaseEnv}
    export APP_ORIGINS="http://127.0.0.1:$APP_PORT,https://127.0.0.1:$APP_PORT,http://localhost:$APP_PORT"
    export LOG_LEVEL="''${LOG_LEVEL:-Info}"
  '';
}
