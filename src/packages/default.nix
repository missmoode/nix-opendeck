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

  opendeck-core = final.callPackage ./opendeck {
    deno = denoPkgs.deno;

    pname = "opendeck-core";

    bundledPlugins = [ ];
  };

  allPlugins = lib.collect lib.isDerivation plugins;
  opendeck-with-plugins = final.callPackage ./opendeck {
    deno = denoPkgs.deno;

    pname = "opendeck-with-plugins";

    bundledPlugins = lib.filter (plugin: plugin.requiredCommands == [ ] && !(plugin ? udev)) allPlugins;
  };

  opendeck = final.callPackage ./opendeck {
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
}
