{
  lib,
  modules,
  pkgs,
  selfPackages,
  treefmtCheck,
}:

let
  packageChecks = pkgs.lib.mapAttrs' (
    name: package: pkgs.lib.nameValuePair "pkgs-${name}" package
  ) selfPackages;
in
{
  pkgs-formatting = treefmtCheck;
}
// packageChecks
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  modules-neko = import ./neko-module.nix {
    inherit lib pkgs;
    module = modules.neko;
  };

  test-neko = import ./nixos-test-neko.nix {
    inherit pkgs;
    module = modules.neko;
  };
}
