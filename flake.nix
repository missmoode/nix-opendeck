{
  description = "Declarative OpenDeck and plugin packaging for Nix";

  nixConfig = {
    extra-substituters = [
      "https://nix-opendeck.cachix.org"
    ];

    extra-trusted-public-keys = [
      "nix-opendeck.cachix.org-1:twvVjvv6Xm9H/m9sD2YQfIDoeUZLWEX5CpokN2An9L8="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Intentionally pinned independently of nixpkgs.
    # Updating Deno can change the fixed-output hashes of Deno dependencies,
    # so this revision should only be changed deliberately.
    #
    # Do NOT use deno-nixpkgs.follows!
    deno-nixpkgs.url = "github:NixOS/nixpkgs/a7868a727837f3c09cee2ce0ca671c76b1589fed";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.easyOverlay
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { final, lib, pkgs, ... }:
        import ./src/packages {
          inherit inputs final lib pkgs;
          pluginLib = (import ./src/lib/plugins) final;
        };

      flake = {
        lib = import ./src/lib;

        homeManagerModules.default =
          { pkgs, ... }@moduleArgs:
          (import ./src/modules/home-manager.nix {
            defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
          })
            moduleArgs;

        overlays.pinned =
          final: prev:
          let
            system = prev.stdenv.hostPlatform.system;
          in
          {
            inherit (self.packages.${system})
              opendeck
              opendeck-core
              opendeck-with-plugins
              ;

            opendeck-plugins = self.legacyPackages.${system}.opendeck-plugins;
          }
          // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
            inherit (self.packages.${system}) opendeck-udev-rules;
          };
      };
    };
}
