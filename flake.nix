{
  description = "NekoGrant - shared browser authority for humans and agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      nixosModules = import ./nix/nixosModules;

      packages = forAllSystems (_: pkgs: import ./nix/packages { inherit pkgs; });

      checks = forAllSystems (
        system: pkgs:
        import ./nix/checks {
          inherit pkgs;
          inherit (nixpkgs) lib;
          modules = inputs.self.nixosModules;
          selfPackages = inputs.self.packages.${system};
          treefmtCheck =
            (import ./nix/formatter {
              inherit pkgs;
              inherit (inputs) treefmt-nix;
            }).check
              inputs.self;
        }
      );

      devShells = forAllSystems (
        _: pkgs:
        import ./nix/devshells {
          inherit pkgs;
          treefmt =
            (import ./nix/formatter {
              inherit pkgs;
              inherit (inputs) treefmt-nix;
            }).wrapper;
        }
      );

      formatter = forAllSystems (
        _: pkgs:
        (import ./nix/formatter {
          inherit pkgs;
          inherit (inputs) treefmt-nix;
        }).wrapper
      );
    };
}
