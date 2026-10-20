# The local app's fixed addresses: one place every development launcher reads them from.
#
# These ports belong to this project. `supabase/config.toml` cannot import Nix, so its `site_url`
# and `additional_redirect_urls` restate `APP_PORT`; change both together.
rec {
  APP_PORT = "5173";
  API_PORT = "3001";
  PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
  # Comma-separated; `Http.ts` reads it through `Config.Array`. There is no default there -- an
  # unset value stops the server rather than silently allowing every origin. Both schemes,
  # matching `supabase/config.toml`'s `site_url` / `additional_redirect_urls` pair.
  APP_ORIGINS = "http://127.0.0.1:${APP_PORT},https://127.0.0.1:${APP_PORT},http://localhost:${APP_PORT}";
  # Local Supabase's Postgres. `Pg.ts` has no defaults either, so the launcher states them; the
  # server only reads them once a feature provides `Sql.PgLive`.
  DB_HOST = "127.0.0.1";
  DB_PORT = "54322";
  DB_USER = "postgres";
  DB_PASSWD = "postgres";
  DB_DATABASE = "postgres";

  # Everything the Node server reads, against local Supabase. `Http.ts` carries no Config defaults,
  # so every launcher names its port and log level.
  serverEnv = ''
    export PUBLIC_SUPABASE_URL="${PUBLIC_SUPABASE_URL}"
    export DB_HOST="${DB_HOST}"
    export DB_PORT="${DB_PORT}"
    export DB_USER="${DB_USER}"
    export DB_PASSWD="${DB_PASSWD}"
    export DB_DATABASE="${DB_DATABASE}"
    export APP_ORIGINS="${APP_ORIGINS}"
    export API_PORT="${API_PORT}"
    export LOG_LEVEL="''${LOG_LEVEL:-Info}"
  '';
}
