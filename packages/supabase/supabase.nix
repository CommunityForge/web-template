_: {
  perSystem =
    { pkgs, buildPnpmPackage, ... }:
    let
      fs = pkgs.lib.fileset;
    in
    {
      packages.supabase = buildPnpmPackage {
        # Set to `pkgs.lib.fakeHash` when dependencies change; the failing build prints the
        # real hash to paste back in.
        hash = "sha256-cag/loo3XuDh4W2jjP4oDLrqPR+F+l9/E3tNl7kVCsI=";
        packageJsonPath = ./package.json;
        # The unit and its one workspace dependency: `tsc -b` builds the referenced project
        # first, so its sources have to be in the sandbox too.
        pnpmWorkspaces = [
          "@replaceme/supabase"
          "@replaceme/domain"
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
          pnpm --filter=@replaceme/supabase build
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          pnpm --filter=@replaceme/supabase check
          pnpm --filter=@replaceme/supabase test --run
          # `--disable-nested-config` stops oxlint discovering `.repos/effect/.oxlintrc.json`,
          # which declares a JS plugin that is not installed.
          oxlint --type-aware --disable-nested-config packages/supabase
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ./packages/supabase/dist ./packages/supabase/src ./packages/supabase/package.json $out/
          runHook postInstall
        '';
      };
    };
}
