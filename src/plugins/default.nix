{
  pkgs,
  pluginLib,
}:

{
  starterpack = pkgs.callPackage ./starterpack.nix {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  xivdeck = pkgs.callPackage ./xivdeck.nix {
    inherit (pluginLib)
      mkYarnOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  homeassistant = pkgs.callPackage ./homeassistant.nix {
    inherit (pluginLib)
      mkNpmOpenDeckPlugin
      ;
  };

  desktopentry = pkgs.callPackage ./desktopentry {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  mpris = pkgs.callPackage ./mpris {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  discord = pkgs.callPackage ./discord.nix {
    inherit (pluginLib)
      mkPrebuiltOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  pipewire = pkgs.callPackage ./pipewire.nix {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };
}
