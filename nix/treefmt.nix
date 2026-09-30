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
  # The shell modules only glob `*.sh`; the setup wizard is a double-clickable
  # `.command`, so pull it in explicitly.
  settings.formatter.shfmt.includes = [ "Setup.command" ];
  settings.formatter.shellcheck.includes = [ "Setup.command" ];
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
    # Don't adjust vendored OpenSpec skills
    ".claude/commands/opsx/**"
    ".claude/skills/openspec-*/**"
  ];
}
