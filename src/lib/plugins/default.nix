pkgs:
let
  mkOpenDeckPlugin = import ./mkOpenDeckPlugin.nix {
    inherit (pkgs)
      lib
      stdenv
      runCommand
      nix-update-script
      jq
      ;
  };

  mkRustOpenDeckPlugin = import ./mkRustOpenDeckPlugin.nix {
    inherit (pkgs)
      lib
      rustPlatform
      stdenv
      ;
    inherit mkOpenDeckPlugin;
  };

  mkNpmOpenDeckPlugin = import ./mkNpmOpenDeckPlugin.nix {
    inherit (pkgs) buildNpmPackage;
    inherit mkOpenDeckPlugin;
  };

  mkYarnOpenDeckPlugin = import ./mkYarnOpenDeckPlugin.nix {
    inherit (pkgs)
      yarnConfigHook
      yarnBuildHook
      nodejs
      stdenv
      fetchYarnDeps
      ;
    inherit mkOpenDeckPlugin;
  };

  mkPrebuiltOpenDeckPlugin = import ./mkPrebuiltOpenDeckPlugin.nix {
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
}
