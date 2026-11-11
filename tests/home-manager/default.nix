{
  self,
  config,
  pkgs,
  homeManagerSource,
}:

let
  homeManager = {
    lib = import "${homeManagerSource}/lib" { inherit (pkgs) lib; };
  };
  module = self.homeManagerModules.default;
  core = config.packages.opendeck-core;

  traditional = import ../../default.nix {
    inherit pkgs;
  };
in
{
  home-manager-module = import ./evaluation.nix {
    inherit
      pkgs
      homeManager
      module
      core
      ;
    inherit (pkgs) lib;

    opendeck = config.packages.opendeck;
    starterpack = config.legacyPackages.opendeck-plugins.nekename.starterpack;
    traditionalModule = traditional.homeManagerModules.default;
    traditionalOpendeck = traditional.opendeck;
  };
}
// (import ./activation {
  inherit pkgs homeManager module;
})
