{
  pkgs,
  pluginLib,
  buildTools,
}:

{
  cronusak = {
    pipewire-audio = pkgs.callPackage ./cronusak/pipewire-audio {
      inherit (pluginLib) mkNpmOpenDeckPlugin;
    };
  };

  elgato = {
    analogclock = pkgs.callPackage ./elgato/analogclock {
      inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
    };
  };

  openactionplugins = {
    desktopentry = pkgs.callPackage ./openactionplugins/desktopentry {
      deno = buildTools.deno;
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };

    discord = pkgs.callPackage ./openactionplugins/discord {
      deno = buildTools.deno;
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };

    mpris = pkgs.callPackage ./openactionplugins/mpris {
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

  cgiesche = {
    homeassistant = pkgs.callPackage ./cgiesche/homeassistant {
      inherit (pluginLib) mkNpmOpenDeckPlugin;
    };
  };

  data-enabler = {
    web-requests = pkgs.callPackage ./data-enabler/web-requests {
      inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
    };
  };

  theca11 = {
    multi-obs-controller = pkgs.callPackage ./theca11/multi-obs-controller {
      inherit (pluginLib) mkNpmOpenDeckPlugin;
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
      inherit (pluginLib) mkNpmOpenDeckPlugin;
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
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

  kazwolfe = {
    xivdeck = pkgs.callPackage ./kazwolfe/xivdeck {
      inherit (pluginLib) mkYarnOpenDeckPlugin;
    };
  };

  mdvictor = {
    volume-controller = pkgs.callPackage ./mdvictor/volume-controller {
      inherit (pluginLib) mkRustOpenDeckPlugin;
    };
  };

}
