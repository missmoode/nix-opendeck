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
    inherit (pluginLib) mkNpmOpenDeckPlugin;
  };

  onairclock = pkgs.callPackage ./onairclock {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
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

  tomatotimer = pkgs.callPackage ./tomatotimer {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
  };

  openweather = pkgs.callPackage ./openweather {
    inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
  };

  xivdeck = pkgs.callPackage ./xivdeck {
    inherit (pluginLib)
      mkYarnOpenDeckPlugin
      mkGitHubReleaseUpdateScript
      ;
  };
}
