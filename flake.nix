{
  description = "A pnpm + TypeScript + Effect monorepo scaffold with reproducible Nix builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Both of these ship their own nixpkgs; without `follows` the flake evaluates three
    # separate trees, one of which lags the root input by months.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      treefmt-nix,
      llm-agents,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      imports = [
        treefmt-nix.flakeModule
        ./packages/core/core.nix
        ./apps/frontend/frontend.nix
      ];
      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          # Rename on fork. This is the other half of the `@replaceme` npm-scope rename
          # described in README.md -- the scope `sed` does not reach Nix derivation names,
          # because they cannot contain `@`.
          projectName = "replaceme";
          pnpm = pkgs.pnpm_10;
          nodejs = pkgs.nodejs-slim_26;
          agentsPkgs = llm-agents.packages.${system};
          buildPnpmPackage = import ./nix/buildPnpmPackage.nix { inherit pkgs nodejs pnpm; };
          treefmt = treefmt-nix.lib.evalModule pkgs (import ./nix/treefmt.nix { inherit pkgs; });
          toolchainPackages = [
            agentsPkgs.claude-code
            agentsPkgs.openspec
            nodejs
            # `.claude/hooks/boundary-guard.sh` parses YAML with this.
            (pkgs.python3.withPackages (
              ps: with ps; [
                pyyaml
              ]
            ))
            pnpm
            pkgs.act
            pkgs.oxfmt
            pkgs.oxlint
            pkgs.tsgolint
            pkgs.typos
            pkgs.nil
            pkgs.nixd
            pkgs.vscode-langservers-extracted
          ];
        in
        {
          _module.args = {
            inherit
              nodejs
              pnpm
              buildPnpmPackage
              ;
          };
          formatter = treefmt.config.build.wrapper;
          checks = config.packages // {
            actionlint =
              let
                workflows = pkgs.lib.fileset.toSource {
                  root = ./.;
                  fileset = ./.github/workflows;
                };
              in
              pkgs.runCommand "actionlint"
                {
                  nativeBuildInputs = [
                    pkgs.actionlint
                    pkgs.shellcheck
                  ];
                }
                ''
                  actionlint -color ${workflows}/.github/workflows/*.yml
                  touch $out
                '';
            formatting = treefmt.config.build.check self;
            spellcheck = pkgs.stdenv.mkDerivation {
              name = "spellcheck";
              dontUnpack = true;
              src = ./.;
              buildInputs = [ pkgs.typos ];
              doCheck = true;
              checkPhase = ''
                cd $src/
                typos --config=typos.toml --format=brief
                touch $out
              '';
            };
          };
          packages.toolchain = pkgs.buildEnv {
            name = "${projectName}-toolchain";
            paths = toolchainPackages;
            ignoreCollisions = true;
          };
          devShells.default = pkgs.mkShell {
            name = "${projectName}-devshell";
            packages = toolchainPackages;
            # `./.claude` doubles as CLAUDE_CONFIG_DIR for Claude Code started from this
            # shell -- see AGENTS.md "Agent configuration". Guarded on `flake.nix` so
            # entering the shell from a subdirectory does not scatter stray `.claude/`
            # directories around the tree.
            shellHook = ''
              if [ -f "$PWD/flake.nix" ]; then
                export CLAUDE_CONFIG_DIR="$PWD/.claude"
                mkdir -p "$CLAUDE_CONFIG_DIR"
              fi
            '';
          };
        };
    };
}
