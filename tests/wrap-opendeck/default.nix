{
  config,
  pkgs,
}:

let
  fixtures = import ./fixtures.nix {
    inherit pkgs;
    wrapOpenDeck = config.legacyPackages.wrapOpenDeck;
  };
in
{
  wrap-opendeck-evaluation = import ./evaluation.nix {
    inherit pkgs fixtures;
  };

  ${if pkgs.stdenvNoCC.hostPlatform.isLinux then "wrap-opendeck-linux" else null} =
    import ./linux.nix
      {
        inherit pkgs fixtures;
      };
}
