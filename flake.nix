{
  description = "NekoGrant - shared browser authority for humans and agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      eachSystem =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      treefmtEval = eachSystem (
        { pkgs, ... }:
        treefmt-nix.lib.evalModule pkgs ./treefmt.nix
      );
    in
    {
      checks = eachSystem (
        { system, ... }:
        {
          formatting = treefmtEval.${system}.config.build.check self;
        }
      );

      devShells = eachSystem (
        { pkgs, system }:
        {
          default = import ./devshell.nix {
            inherit pkgs;
            treefmt = treefmtEval.${system}.config.build.wrapper;
          };
        }
      );

      packages = eachSystem (
        { pkgs, ... }:
        {
          neko-image = pkgs.callPackage ./packages/neko-image { };
        }
      );

      formatter = eachSystem ({ system, ... }: treefmtEval.${system}.config.build.wrapper);
    };
}
