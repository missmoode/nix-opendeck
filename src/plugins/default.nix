{
  pkgs,
  pluginLib,
  buildTools,
}:

{
  elgato = {
    analogclock = pkgs.callPackage ./elgato/analogclock {
      inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
    };
  };

  openactionplugins = {
    desktopentry = pkgs.callPackage ./openactionplugins/desktopentry {
      deno = buildTools.deno;
      inherit (pluginLib)
        mkRustOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };

    discord = pkgs.callPackage ./openactionplugins/discord {
      deno = buildTools.deno;
      inherit (pluginLib)
        mkRustOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };

    mpris = pkgs.callPackage ./openactionplugins/mpris {
      inherit (pluginLib)
        mkRustOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };
  };

  cgiesche = {
    homeassistant = pkgs.callPackage ./cgiesche/homeassistant {
      inherit (pluginLib)
        mkNpmOpenDeckPlugin
        ;
    };
  };

  the_ca11 = {
    multi-obs-controller = pkgs.callPackage ./the_ca11/multi-obs-controller {
      inherit (pluginLib)
        mkNpmOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };
  };

  wortkrieg = {
    onairclock = pkgs.callPackage ./wortkrieg/onairclock {
      inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
    };
  };

  sjourdois = {
    pipewire = pkgs.callPackage ./sjourdois/pipewire {
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

  kahikara = {
    redline-monitor = pkgs.callPackage ./kahikara/redline-monitor {
      inherit (pluginLib)
        mkNpmOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };
  };

  nekename = {
    starterpack = pkgs.callPackage ./nekename/starterpack {
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

  gdwhisper = {
    tikclock = pkgs.callPackage ./gdwhisper/tikclock {
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

  gallowaylabs = {
    tomato-timer = pkgs.callPackage ./gallowaylabs/tomato-timer {
      inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
    };
  };

  jfms7s = {
    weather = pkgs.callPackage ./jfms7s/weather {
      inherit (pluginLib)
        mkRustOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };
  };

  kazwolfe = {
    xivdeck = pkgs.callPackage ./kazwolfe/xivdeck {
      inherit (pluginLib)
        mkYarnOpenDeckPlugin
        mkGitHubReleaseUpdateScript
        ;
    };
  };
}
