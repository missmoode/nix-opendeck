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
      checks =
        (import ./home-manager {
          inherit
            self
            config
            pkgs
            homeManagerSource
            ;
        })
        // (import ./wrap-opendeck {
          inherit config pkgs;
        })
        // {
          traditional-entrypoints = import ./traditional.nix {
            inherit pkgs;
            inherit (pkgs) lib;
          };
        };
    };
}
