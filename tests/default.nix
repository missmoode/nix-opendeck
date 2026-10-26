{ inputs, self, ... }:

{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      checks = {
        home-manager-module = import ./home-manager.nix {
          inherit pkgs;
          inherit (pkgs) lib;

          homeManager = inputs.home-manager;
          module = self.homeManagerModules.default;

          opendeck = config.packages.opendeck;
          core = config.packages.opendeck-core;
          starterpack = config.legacyPackages.opendeck-plugins.nekename.starterpack;
        };
      }
      // (
        let
          fixtures = import ./wrap-opendeck/fixtures.nix {
            inherit pkgs;
            wrapOpenDeck = config.legacyPackages.wrapOpenDeck;
          };
        in
        {
          wrap-opendeck-evaluation = import ./wrap-opendeck/evaluation.nix {
            inherit pkgs fixtures;
          };

          ${if pkgs.stdenvNoCC.hostPlatform.isLinux then "wrap-opendeck-linux" else null} =
            import ./wrap-opendeck/linux.nix
              {
                inherit pkgs fixtures;
              };
        }
      );
    };
}
