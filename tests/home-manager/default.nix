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
  };
}
// (import ./activation {
  inherit pkgs homeManager module;
})
