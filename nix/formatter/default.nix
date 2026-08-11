{
  pkgs,
  treefmt-nix,
}:

let
  treefmtEval = treefmt-nix.lib.evalModule pkgs {
    projectRootFile = "flake.nix";

    programs = {
      deadnix.enable = true;
      gofmt.enable = true;
      golangci-lint.enable = true;
      nixfmt.enable = true;
      statix.enable = true;
    };
  };
in
{
  wrapper = treefmtEval.config.build.wrapper;
  check = treefmtEval.config.build.check;
}
