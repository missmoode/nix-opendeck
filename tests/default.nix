{ inputs, self, ... }:

{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.home-manager-module = import ./home-manager.nix {
        inherit pkgs;
        inherit (pkgs) lib;

        homeManager = inputs.home-manager;
        module = self.homeManagerModules.default;

        opendeck = config.packages.opendeck;
        core = config.packages.opendeck-core;
        starterpack = config.legacyPackages.opendeck-plugins.nekename.starterpack;
      };
    };
}
