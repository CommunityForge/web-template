{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  # `bin/*.sh` and the `.claude/hooks/*.sh` boundary guard are load-bearing and were
  # previously unformatted and unchecked by anything.
  programs.shfmt.enable = true;
  programs.shellcheck.enable = true;
  # shfmt de-indents `case` arms by default, which reads worse than the style already
  # used in `.claude/hooks/boundary-guard.sh`. `-ci` keeps them indented.
  settings.formatter.shfmt.options = [ "-ci" ];
  programs.oxfmt = {
    enable = true;
    package = pkgs.oxfmt;
  };

  settings.global.excludes = [
    ".repos/**"
    "pnpm-lock.yaml"
    "flake.lock"
    "*.tsbuildinfo"
    # Vendored third-party agent skill bundles -- not ours to reformat.
    ".agents/**"
  ];
}
