{
  pkgs,
  pluginLib,
}:

{
  analogclock = pkgs.callPackage ./analogclock {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
  };

  desktopentry = pkgs.callPackage ./desktopentry {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  oadiscord = pkgs.callPackage ./discord {
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

  multi-obs-controller = pkgs.callPackage ./multi-obs-controller {
    inherit (pluginLib)
      mkNpmOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  onairclock = pkgs.callPackage ./onairclock {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
  };

  pipewire = pkgs.callPackage ./pipewire {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  redline-monitor = pkgs.callPackage ./redline-monitor {
    inherit (pluginLib)
      mkNpmOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  starterpack = pkgs.callPackage ./starterpack {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  tikclock = pkgs.callPackage ./tikclock {
    inherit (pluginLib) mkRustOpenDeckPlugin;
  };

  tomatotimer = pkgs.callPackage ./tomatotimer {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
  };

  jfms7s-weather = pkgs.callPackage ./jfms7s-weather {
    inherit (pluginLib)
      mkRustOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };

  xivdeck = pkgs.callPackage ./xivdeck {
    inherit (pluginLib)
      mkYarnOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };
}
