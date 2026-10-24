{
  inputs,
  final,
  lib,
  pkgs,
  pluginLib,
}:
let
  denoPkgs = import inputs.deno-nixpkgs {
    system = pkgs.stdenv.buildPlatform.system;
  };

  buildTools = {
    deno = denoPkgs.deno;
  };

  plugins = import ./plugins {
    pkgs = final;

    inherit pluginLib buildTools;
  };

  # The only OpenDeck package requiring Rust/Tauri compilation.
  opendeck-core = final.callPackage ./opendeck {
    deno = denoPkgs.deno;
  };

  # Provide the core as a default while allowing callers to override it.
  wrapOpenDeckImpl = final.callPackage ./wrapOpenDeck.nix { };

  wrapOpenDeck =
    args:
    wrapOpenDeckImpl (
      {
        package = opendeck-core;
      }
      // args
    );

  allPlugins = lib.collect lib.isDerivation plugins;

  opendeck = wrapOpenDeck {
    pname = "opendeck";

    plugins = [
      plugins.nekename.starterpack
    ];
  };

  opendeck-with-plugins = wrapOpenDeck {
    pname = "opendeck-with-plugins";

    plugins = lib.filter (plugin: plugin.requiredCommands == [ ] && !(plugin ? udev)) allPlugins;
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
    inherit wrapOpenDeck;

    opendeck-plugins = lib.recurseIntoAttrs (
      lib.mapAttrs (_: ownerPlugins: lib.recurseIntoAttrs ownerPlugins) plugins
    );
  };

  overlayAttrs = {
    inherit
      opendeck
      opendeck-core
      opendeck-with-plugins
      wrapOpenDeck
      ;

    opendeck-plugins = plugins;
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    inherit opendeck-udev-rules;
  };
}
