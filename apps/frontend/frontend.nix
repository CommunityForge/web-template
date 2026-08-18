_: {
  perSystem =
    { pkgs, buildPnpmPackage, ... }:
    let
      fs = pkgs.lib.fileset;
    in
    {
      packages.frontend = buildPnpmPackage {
        hash = "sha256-+dcroew7TGWwUdrE/pOVrmH6/VV/rpKo8KRNvDrfcz0=";
        packageJsonPath = ./package.json;
        pnpmWorkspaces = [ "@replaceme/frontend" ];
        extraSrcs = fs.unions [
          ./package.json
          ./tsconfig.json
          ./tsconfig.app.json
          ./tsconfig.node.json
          ./vite.config.ts
          ./vitest.config.ts
          ./index.html
          ./public
          ./src
          ./test
          ../../.oxlintrc.json
        ];
        nativeBuildInputs = [ pkgs.oxlint ];
        doCheck = true;
        buildPhase = ''
          runHook preBuild
          pnpm --filter=@replaceme/frontend build
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          pnpm --filter=@replaceme/frontend check
          pnpm --filter=@replaceme/frontend test --run
          oxlint --type-aware --disable-nested-config apps/frontend
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ./apps/frontend/dist/. $out/
          runHook postInstall
        '';
      };
    };
}
