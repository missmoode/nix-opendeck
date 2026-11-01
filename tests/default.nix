{ self, ... }:

let
  # Test-only Home Manager source, pinned independently of the public flake inputs.
  # Update rev and narHash together when updating the test dependency.
  homeManagerSource =
    (fetchTree {
      type = "github";
      owner = "nix-community";
      repo = "home-manager";
      rev = "7db163b2aee7e410e396b48aed02f646d742b9b8";
      narHash = "sha256-fXVURa0+CSCgaxLt8tmPNJq2U+fGYOwbk5j2YUe7kSc=";
    }).outPath;
in
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

          homeManager = {
            lib = import "${homeManagerSource}/lib" { inherit (pkgs) lib; };
          };
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
