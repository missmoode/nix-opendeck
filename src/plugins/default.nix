{
  pkgs,
  pluginLib,
}:

{
  starterpack = pkgs.callPackage ./starterpack {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  xivdeck = pkgs.callPackage ./xivdeck {
    inherit (pluginLib)
      mkYarnOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  homeassistant = pkgs.callPackage ./homeassistant {
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

  discord = pkgs.callPackage ./discord {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  pipewire = pkgs.callPackage ./pipewire {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };
}
