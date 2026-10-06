{
  description = "OpenDeck - Linux software for your Elgato Stream Deck";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Intentionally independent from nixpkgs, so that differences
    # in the builder's deno package don't change the hash of the
    # dependencies.
    #
    # Do NOT use deno-nixpkgs.follows!
    deno-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
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

          opendeck-with-plugins = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck-with-plugins";

            bundledPlugins = lib.filter (plugin: plugin.requiredCommands == [ ]) (lib.attrValues plugins);
          };

          opendeck = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck";

            bundledPlugins = [
              plugins.starterpack
            ];

            updateScript = pluginLib.mkGitHubReleaseUpdateScript {
              owner = "nekename";
              repo = "OpenDeck";
            };
          };
        in
        {
          packages = {
            inherit
              opendeck
              opendeck-core
              opendeck-with-plugins
              ;

            default = opendeck;
          };

          legacyPackages = {
            opendeck-plugins = plugins // {
              recurseForDerivations = true;
            };
          };

          overlayAttrs = {
            inherit
              opendeck
              opendeck-core
              opendeck-with-plugins
              ;

            opendeck-plugins = plugins;
          };
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
            defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
          })
            moduleArgs;

        homeManagerModules.default =
          { pkgs, ... }@moduleArgs:
          (import ./src/modules/home-manager.nix {
            defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
          })
            moduleArgs;
      };
    };
}
