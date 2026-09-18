{
  description = "A pnpm + TypeScript + Effect monorepo scaffold with reproducible Nix builds";

  # Inputs use `git+https` with shallow fetches instead of `github:`: Claude
  # cloud sessions route GitHub API/tarball requests through a proxy scoped to
  # the session's own repo (403 for every other repo), while plain git fetches
  # of public repos pass. The nested overrides keep transitive inputs off the
  # tarball fetcher too -- `grep '"type": "github"' flake.lock` must stay empty.
  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixpkgs-unstable&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    llm-agents = {
      url = "git+https://github.com/numtide/llm-agents.nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.systems.url = "git+https://github.com/nix-systems/default?shallow=1";
      inputs.bun2nix.url = "git+https://github.com/Mic92/bun2nix?ref=fix-structured-attrs-hook&shallow=1";
    };
    treefmt-nix = {
      url = "git+https://github.com/numtide/treefmt-nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "git+https://github.com/cachix/git-hooks.nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.url = "git+https://github.com/NixOS/flake-compat?shallow=1";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      treefmt-nix,
      llm-agents,
      git-hooks-nix,
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
        git-hooks-nix.flakeModule
        ./packages/lib/lib.nix
        ./packages/domain/domain.nix
        ./packages/db/db.nix
        ./packages/supabase/supabase.nix
        ./apps/frontend/frontend.nix
        ./apps/server/server.nix
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
          # The `bash -n` equivalent for the Windows wizard: treefmt has no
          # PowerShell formatter, so parse errors are caught here instead. pwsh 7
          # accepts syntax Windows PowerShell 5.1 rejects (&&/|| chains, ternary),
          # so the 5.1 floor itself is held by review, not this check.
          psparseScript = pkgs.writeText "psparse.ps1" ''
            $errs = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$null, [ref]$errs)
            if ($errs.Count -gt 0) {
              $errs | ForEach-Object { Write-Output ($_.ToString()) }
              exit 1
            }
          '';
          toolchainPackages = [
            agentsPkgs.openspec
            nodejs
            pnpm
            # Hook scripts prepend `.devshell/bin` to PATH when the out-link
            # exists, pinning these over the host's BSD tools in GUI-launched
            # clients -- see AGENTS.md "Agents in a sandboxed client". The dev
            # shell itself already carries them via stdenv.
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.act
            # `gh` backs Setup.command's GitHub stage (browser sign-in that also
            # configures git's credential helper) and the wizard library's
            # set_secret/set_var helpers.
            pkgs.gh
            pkgs.supabase-cli
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
            psparse = pkgs.runCommand "psparse" { nativeBuildInputs = [ pkgs.powershell ]; } ''
              # pwsh insists on a writable config directory, even with -NoProfile.
              export HOME="$TMPDIR"
              pwsh -NoProfile -File ${psparseScript} ${./Setup.ps1}
              touch $out
            '';
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
          pre-commit = {
            check.enable = false;
            settings.hooks = {
              nix-fmt = {
                enable = true;
                name = "nix fmt";
                entry = "nix fmt";
                pass_filenames = false;
                stages = [ "pre-commit" ];
              };

              flake-check = {
                enable = true;
                name = "nix flake check";
                entry = "nix flake check";
                pass_filenames = false;
                stages = [ "pre-push" ];
              };
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
              ${config.pre-commit.shellHook}
              if [ -f "$PWD/flake.nix" ]; then
                export CLAUDE_CONFIG_DIR="$PWD/.claude"
                mkdir -p "$CLAUDE_CONFIG_DIR"
              fi
            '';
          };
        };
    };
}
