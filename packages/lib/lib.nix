_: {
  perSystem =
    { pkgs, buildPnpmPackage, ... }:
    let
      fs = pkgs.lib.fileset;
    in
    {
      packages.lib = buildPnpmPackage {
        # Set to `pkgs.lib.fakeHash` when dependencies change; the failing build prints the
        # real hash to paste back in.
        hash = "sha256-9bcoU1YiTDjkPCixTw6U0RAxnHOpDnvwzaBLPf7Z7Ls=";
        packageJsonPath = ./package.json;
        pnpmWorkspaces = [ "@landbank/lib" ];
        # Explicit rather than `fs.unions [ ./. ]`: a bare directory sweeps node_modules/,
        # dist/ and tsbuildinfo into the sandbox, which only looks clean because git-tracked
        # filtering hides it. A stale dist/ would silently satisfy `tsc -b` incrementality.
        extraSrcs = fs.unions [
          ./package.json
          ./tsconfig.json
          ./vitest.config.ts
          ./src
          ./test
          # oxlint resolves its config -- and its `overrides.files` globs -- relative to the
          # config file's directory, so it has to sit at the source root.
          ../../.oxlintrc.json
        ];
        nativeBuildInputs = [ pkgs.oxlint ];
        doCheck = true;
        buildPhase = ''
          runHook preBuild
          pnpm --filter=@landbank/lib build
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          pnpm --filter=@landbank/lib check
          pnpm --filter=@landbank/lib test --run
          # `--disable-nested-config` stops oxlint discovering `.repos/effect/.oxlintrc.json`,
          # which declares a JS plugin that is not installed.
          oxlint --type-aware --disable-nested-config packages/lib
          runHook postCheck
        '';
        # `dist/.` rather than `dist/*`: the glob fails on an empty directory and drops dotfiles.
        # Ship src/ and the manifest too so $out is a consumable package, not a pile of .js.
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ./packages/lib/dist ./packages/lib/src ./packages/lib/package.json $out/
          runHook postInstall
        '';
      };
    };
}
