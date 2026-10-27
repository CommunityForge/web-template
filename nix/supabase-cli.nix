# The Supabase CLI at a release new enough for the native stack runtime (`[experimental] stack`,
# `supabase start --runtime native`). nixpkgs still ships an older release; drop this file once
# `pkgs.supabase-cli` reaches the same version.
#
# The release binaries, not a source build: from 2.120 the CLI is a Bun-compiled program with a Go
# sidecar, built from a Bun/pnpm monorepo the Nix sandbox cannot fetch for. The hashes are the
# release's own published checksums. The program finds `supabase-go` beside its own executable, so
# both stay in `bin/`.
#
# Usage statistics are OFF: `supabase` is a wrapper setting `SUPABASE_TELEMETRY_DISABLED=1`, which the
# CLI honors and passes on to the sidecar. Every caller (dev shell, launchers, CI) runs the wrapper.
#
# NOT stripped and NOT patched: a Bun-compiled binary carries its program as a payload that strip
# and patchelf damage. The Linux build therefore runs on a host with a standard glibc loader (WSL
# Ubuntu, CI's Ubuntu runners), not on bare NixOS.
{ pkgs }:
let
  version = "2.122.0";
  platforms = {
    aarch64-darwin = {
      asset = "darwin_arm64";
      hash = "sha256-/oel+XgdVCPb1eu6LVpuGlQdAXVNFJQcV0lS5WleqrA=";
    };
    aarch64-linux = {
      asset = "linux_arm64";
      hash = "sha256-iYC0YESroIY/JqG0E0pJjSx03w2t8kKJu0+qhnKVEcw=";
    };
    x86_64-linux = {
      asset = "linux_amd64";
      hash = "sha256-We0GaEe5jXRhxg6RCdQMq2uXVhd84G67BbUTOFGfUTY=";
    };
  };
  platform = platforms.${pkgs.stdenv.hostPlatform.system};
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "supabase-cli";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_${platform.asset}.tar.gz";
    inherit (platform) hash;
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin supabase supabase-go
    wrapProgram $out/bin/supabase --set SUPABASE_TELEMETRY_DISABLED 1
    runHook postInstall
  '';
  meta = {
    description = "Supabase CLI";
    homepage = "https://github.com/supabase/cli";
    license = pkgs.lib.licenses.mit;
    mainProgram = "supabase";
    platforms = builtins.attrNames platforms;
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
  };
}
