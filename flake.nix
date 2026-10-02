{
  description = "OpenDeck - Linux software for your Elgato Stream Deck";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      mkPluginLib =
        pkgs:
        let
          mkGitHubReleaseUpdateScript = import ./src/lib/mkGitHubReleaseUpdateScript.nix {
            inherit (pkgs)
              lib
              writeShellApplication
              curl
              jq
              nix
              nix-update
              ;
          };

          mkOpenDeckPlugin = import ./src/lib/mkOpenDeckPlugin.nix {
            inherit (pkgs) nix-update-script;
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
            mkGitHubReleaseUpdateScript
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
      ];

      perSystem =
        {
          lib,
          pkgs,
          ...
        }:
        let
          pluginLib = mkPluginLib pkgs;

          plugins = import ./src/plugins {
            inherit pkgs pluginLib;
          };

          pluginPackages = lib.mapAttrs' (name: plugin: {
            name = "opendeck-plugin-${name}";
            value = plugin;
          }) plugins;

          opendeck-core = pkgs.callPackage ./src/opendeck.nix {
            bundledPlugins = [ ];
          };

          opendeck = pkgs.callPackage ./src/opendeck.nix {
            bundledPlugins = [
              plugins.starterpack
            ];
          };
        in
        {
          packages = {
            inherit
              opendeck
              opendeck-core
              ;

            default = opendeck;
          }
          // pluginPackages;

          overlayAttrs = {
            inherit
              opendeck
              opendeck-core
              ;
          }
          // pluginPackages;
        };

      flake = {
        lib = {
          mkOpenDeckPlugin = import ./src/lib/mkOpenDeckPlugin.nix;

          mkRustOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkRustOpenDeckPlugin;

          mkNpmOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkNpmOpenDeckPlugin;

          mkYarnOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkYarnOpenDeckPlugin;

          mkPrebuiltOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkPrebuiltOpenDeckPlugin;

          mkGitHubReleaseUpdateScript = pkgs: (mkPluginLib pkgs).mkGitHubReleaseUpdateScript;
        };

        nixosModules.default =
          { pkgs, ... }@moduleArgs:
          (import ./src/modules/nixos.nix {
            defaultPackage = pkgs.opendeck;
          })
            moduleArgs;

        homeManagerModules.default =
          { pkgs, ... }@moduleArgs:
          (import ./src/modules/home-manager.nix {
            defaultPackage = pkgs.opendeck;
          })
            moduleArgs;
      };
    };
}
