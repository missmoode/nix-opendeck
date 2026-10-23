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
    let
      mkPluginLib =
        pkgs:
        let
          mkOpenDeckPlugin = import ./src/lib/mkOpenDeckPlugin.nix {
            inherit (pkgs)
              lib
              stdenv
              runCommand
              nix-update-script
              jq
              ;
          };

          mkRustOpenDeckPlugin = import ./src/lib/mkRustOpenDeckPlugin.nix {
            inherit (pkgs)
              lib
              rustPlatform
              stdenv
              ;
            inherit mkOpenDeckPlugin;
          };

          mkNpmOpenDeckPlugin = import ./src/lib/mkNpmOpenDeckPlugin.nix {
            inherit (pkgs) buildNpmPackage;
            inherit mkOpenDeckPlugin;
          };

          mkYarnOpenDeckPlugin = import ./src/lib/mkYarnOpenDeckPlugin.nix {
            inherit (pkgs)
              yarnConfigHook
              yarnBuildHook
              nodejs
              stdenv
              fetchYarnDeps
              ;
            inherit mkOpenDeckPlugin;
          };

          mkPrebuiltOpenDeckPlugin = import ./src/lib/mkPrebuiltOpenDeckPlugin.nix {
            inherit (pkgs) stdenv;
            inherit mkOpenDeckPlugin;
          };
        in
        {
          inherit
            mkOpenDeckPlugin
            mkRustOpenDeckPlugin
            mkNpmOpenDeckPlugin
            mkYarnOpenDeckPlugin
            mkPrebuiltOpenDeckPlugin
            ;
        };

    in
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
        {
          final,
          lib,
          pkgs,
          ...
        }:
        let
          denoPkgs = import inputs.deno-nixpkgs {
            system = pkgs.stdenv.buildPlatform.system;
          };

          buildTools = {
            deno = denoPkgs.deno;
          };

          pluginLib = mkPluginLib final;

          plugins = import ./src/plugins {
            pkgs = final;

            inherit pluginLib buildTools;
          };

          opendeck-core = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck-core";

            bundledPlugins = [ ];
          };

          allPlugins = lib.collect lib.isDerivation plugins;
          opendeck-with-plugins = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck-with-plugins";

            bundledPlugins = lib.filter (plugin: plugin.requiredCommands == [ ] && !(plugin ? udev)) allPlugins;
          };

          opendeck = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck";

            bundledPlugins = [
              plugins.nekename.starterpack
            ];
          };

          opendeck-udev-rules = opendeck-core.udev;
        in
        {
          packages = {
            inherit
              opendeck
              opendeck-core
              opendeck-with-plugins
              ;

            default = opendeck;
          }
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            inherit opendeck-udev-rules;
          };

          legacyPackages = {
            opendeck-plugins = lib.recurseIntoAttrs (
              lib.mapAttrs (_: ownerPlugins: lib.recurseIntoAttrs ownerPlugins) plugins
            );
          };

          overlayAttrs = {
            inherit
              opendeck
              opendeck-core
              opendeck-with-plugins
              ;

            opendeck-plugins = plugins;
          }
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            inherit opendeck-udev-rules;
          };
        };

      flake = {
        lib = {
          mkOpenDeckPlugin = import ./src/lib/mkOpenDeckPlugin.nix;

          mkRustOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkRustOpenDeckPlugin;

          mkNpmOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkNpmOpenDeckPlugin;

          mkYarnOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkYarnOpenDeckPlugin;

          mkPrebuiltOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkPrebuiltOpenDeckPlugin;
        };

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
