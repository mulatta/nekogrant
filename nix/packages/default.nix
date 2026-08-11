{ pkgs }:

pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  neko-image = pkgs.callPackage ./neko-image { };
}
