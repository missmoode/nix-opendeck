# Public plugin-author API. Every helper accepts a Nixpkgs package set first.
let
  mkPluginLib = import ./plugins;
in
{
  mkOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkOpenDeckPlugin;
  mkRustOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkRustOpenDeckPlugin;
  mkNpmOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkNpmOpenDeckPlugin;
  mkYarnOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkYarnOpenDeckPlugin;
  mkPrebuiltOpenDeckPlugin = pkgs: (mkPluginLib pkgs).mkPrebuiltOpenDeckPlugin;

  wrapOpenDeck = pkgs: pkgs.callPackage ../packages/wrapOpenDeck.nix { };
}
