{
  pkgs,
  pluginLib,
}:

{

  desktopentry = pkgs.callPackage ./desktopentry {
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

  homeassistant = pkgs.callPackage ./homeassistant {
    inherit (pluginLib)
      mkNpmOpenDeckPlugin
      ;
  };

  mpris = pkgs.callPackage ./mpris {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  pipewire = pkgs.callPackage ./pipewire {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  starterpack = pkgs.callPackage ./starterpack {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  tikclock = pkgs.callPackage ./tikclock {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  xivdeck = pkgs.callPackage ./xivdeck {
    inherit (pluginLib)
      mkYarnOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };
}
