# buildPnpmPackage.nix
# ===
# Wraps `buildNpmPackage` with defaults suited to a pnpm workspace.
#
# The hard problem this solves: `pnpm.fetchDeps` fetches dependencies for the *whole* workspace,
# which means every derivation's fixed-output hash changes whenever any unrelated package's
# dependencies change. The overridden `installPhase` below rewrites `pnpm-workspace.yaml`'s
# `packages:` list down to just the units named in `pnpmWorkspaces` before fetching, so each
# derivation only sees -- and only hashes -- its own dependency closure.
#
# Path literals resolve relative to *this file*, so `root = ./..` is always the repo root
# regardless of where a calling module lives. Callers therefore pass repo-root-relative
# `extraSrcs` (`./.` for their own directory, `../../packages/foo` for a dependency), and the
# derivation's working directory mirrors the repo layout: a package at `packages/lib` builds
# into `$PWD/packages/lib/dist`.

{
  pnpm,
  nodejs,
  pkgs,
  ...
}:
args@{
  # to derive pname and version
  packageJsonPath,
  # to provision sources additional to monorepo boilerplate
  extraSrcs,
  # workspace project names required for build (e.g. anything with a "workspace:*" version declaration)
  pnpmWorkspaces ? [ ],
  hash ? pkgs.lib.fakeHash,
  ...
}:

let
  fs = pkgs.lib.fileset;
  src = fs.toSource {
    root = ./..;
    fileset = fs.union extraSrcs (
      fs.unions [
        # pnpm workspace root
        ../package.json
        ../pnpm-lock.yaml
        ../pnpm-workspace.yaml
        # `pnpm --filter=X check` -- every leaf tsconfig extends this
        ../tsconfig.base.json
        # `pnpm --filter=X test` -- every unit's vitest.config.ts imports ../../vitest.shared.js,
        # which in turn references vitest.setup.ts. Omitting these makes `checkPhase` fail to
        # resolve its own config.
        ../vitest.shared.ts
        ../vitest.setup.ts
      ]
    );
  };
  packageJson = pkgs.lib.importJSON packageJsonPath;
  # Derivation names may not contain `@` or `/`. stdenv sanitizes, but leaves an ugly
  # leading dash in the store path -- normalize up front instead.
  pname = pkgs.lib.replaceStrings [ "@" "/" ] [ "" "-" ] packageJson.name;
  inherit (packageJson) version;
  # Top-level `fetchPnpmDeps`/`pnpmConfigHook`; the `pnpm.fetchDeps`/`pnpm.configHook`
  # passthru attributes are deprecated. `pnpm` is still threaded through so the pinned
  # major version drives both the fetch and the install hook.
  pnpmDeps =
    (pkgs.fetchPnpmDeps {
      inherit pnpm;
      inherit
        hash
        pname
        pnpmWorkspaces
        src
        version
        ;
      fetcherVersion = 3;
    }).overrideAttrs
      (
        super:
        let
          filterFlags = pkgs.lib.map (p: "--filter=${p}") (super.pnpmWorkspaces or [ ]);
        in
        {
          installPhase = ''
            runHook preInstall
            export HOME=$(mktemp -d)
            mkdir $out
            storePath=$(mktemp -d)
            pnpm config set store-dir $storePath
            pnpm config set side-effects-cache false
            pnpm config set update-notifier false
            pnpm config set manage-package-manager-versions false
            mapfile -t wanted_names <<EOF
            ${pkgs.lib.concatStringsSep "\n" pnpmWorkspaces}
            EOF
            mapfile -t pkgjsons < <(
              find . \
                -path '*/node_modules/*' -prune -o \
                -type f -name package.json -print
            )

            declare -a dirs=()

            for pj in ''\${pkgjsons[@]}; do
              name="$(jq -r '.name // empty' "$pj")"
              [[ -z "$name" ]] && continue
              for wanted in ''\${wanted_names[@]}; do
                if [[ "$name" == "$wanted" ]]; then
                  d="$(dirname "$pj")"
                  d="''\${d#./}"
                  dirs+=("$d")
                  break
                fi
              done
            done

            declare -A seen=()
            declare -a uniq_dirs=()
            for d in ''\${dirs[@]}; do
              if [[ -n "$d" && -z "''\${seen[$d]:-}" ]]; then
                seen["$d"]=1
                uniq_dirs+=("$d")
              fi
            done

            if [[ ''\${#uniq_dirs[@]} -eq 0 ]]; then
              echo "No workspace directories matched pnpmWorkspaces:" >&2
              printf '  - %s\n' ''\${wanted_names[@]} >&2
              exit 1
            fi

            TMP_DIR="$(mktemp -d)"
            trap 'rm -rf "$TMP_DIR"' EXIT

            if [[ ! -f pnpm-workspace.yaml ]]; then
              echo "pnpm-workspace.yaml not found in $PWD" >&2
              exit 1
            fi

            # Narrow `packages:` to the requested subset so the FOD hash depends only on this
            # unit's closure.
            PKGFILE="$TMP_DIR/_packages.yaml"
            {
              echo "packages:"
              for d in ''\${uniq_dirs[@]}; do
                printf '  - %s\n' "$d"
              done
            } > "$PKGFILE"

            ${pkgs.yq-go}/bin/yq eval-all -i '
              select(fileIndex == 0) *
              {"packages": (select(fileIndex == 1).packages)}
            ' pnpm-workspace.yaml "$PKGFILE"

            echo "Narrowed workspace to:"
            ${pkgs.yq-go}/bin/yq -r '.packages[]' pnpm-workspace.yaml | sed 's/^/  - /'

            # Produce a pruned lockfile derived from the shared root lockfile.
            pnpm install \
              --force \
              --lockfile-only \
              --ignore-scripts \
              ${pkgs.lib.escapeShellArgs filterFlags} \
              --registry="$NIX_NPM_REGISTRY" || {
              echo "Lockfile-only pass failed. Ensure root pnpm-lock.yaml matches the workspace."
              exit 1
            }

            # Fetch into the store.
            pnpm install \
              --force \
              --ignore-scripts \
              --registry="$NIX_NPM_REGISTRY" \
              --frozen-lockfile

            echo 3 > $out/.fetcher-version

            runHook postInstall
          '';
        }
      );
in
pkgs.buildNpmPackage (
  (builtins.removeAttrs args [ "extraSrcs" ])
  // {
    inherit
      pname
      pnpmDeps
      pnpmWorkspaces
      src
      version
      nodejs
      ;
    npmConfigHook = pkgs.pnpmConfigHook.override { inherit pnpm; };
    npmDeps = pnpmDeps;
    # The Node this unit was built against, for whatever runs its output (a NixOS module's
    # systemd unit, say) -- so bumping `nodejs` in `flake.nix` moves the build and the runtime
    # together instead of leaving a second hardcoded attribute to forget.
    passthru = (args.passthru or { }) // {
      inherit nodejs;
    };
    # `pnpmConfigHook` shells out to `pnpm`, and the build phases below invoke
    # `pnpm --filter=...` directly. Merged rather than assigned so callers can add their own.
    nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [ pnpm ];
    NODE_OPTIONS = "--max-old-space-size=8192";
  }
)
