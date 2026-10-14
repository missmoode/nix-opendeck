{
  description = "OpenDeck - Linux software for your Elgato Stream Deck";

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

          allPlugins = lib.collect lib.isDerivation plugins;
          opendeck-with-plugins = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck-with-plugins";

            bundledPlugins = lib.filter (plugin: plugin.requiredCommands == [ ]) allPlugins;
          };

          opendeck = final.callPackage ./src/opendeck.nix {
            deno = denoPkgs.deno;

            pname = "opendeck";

            bundledPlugins = [
              plugins.nekename.starterpack
            ];
          };

          opendeck-udev-rules = final.runCommand "opendeck-udev-rules-${opendeck-core.version}" { } ''
            install -Dm644 \
              ${opendeck-core.src}/src-tauri/bundle/40-streamdeck.rules \
              "$out/lib/udev/rules.d/40-streamdeck.rules"
          '';
        in
        {
          packages = {
            inherit
              opendeck
              opendeck-core
              opendeck-with-plugins
              opendeck-udev-rules
              ;

            default = opendeck;
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
              opendeck-udev-rules
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
        };

        nixosModules.default =
          { pkgs, ... }@moduleArgs:
          (import ./src/modules/nixos.nix {
            defaultUdevPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.opendeck-udev-rules;
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
