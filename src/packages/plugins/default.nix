{
  pkgs,
  pluginLib,
  buildTools,
}:

let
  plugins = {
    "4ndv" = {
      akp03 = pkgs.callPackage ./4ndv/akp03 {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };

      akp153 = pkgs.callPackage ./4ndv/akp153 {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };

    ambiso = {
      akp05 = pkgs.callPackage ./ambiso/akp05 {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };

    babs = {
      rotary-command = pkgs.callPackage ./babs/rotary-command {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };

    biviale = {
      pwsounddeck = pkgs.callPackage ./biviale/pwsounddeck {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };

    cronusak = {
      pipewire-audio = pkgs.callPackage ./cronusak/pipewire-audio {
        inherit (pluginLib) mkNpmOpenDeckPlugin;
      };
    };

    # Temporarily disabled pending upstream logging improvements.
    # See https://github.com/danmaxis/hyprstream/issues/1
    #
    # danmaxis = {
    #   hyprstream = pkgs.callPackage ./danmaxis/hyprstream {
    #     inherit (pluginLib) mkNpmOpenDeckPlugin;
    #   };

    #   hyprstream-media = pkgs.callPackage ./danmaxis/hyprstream-media {
    #     inherit (pluginLib) mkNpmOpenDeckPlugin;
    #   };

    #   hyprstream-monitors = pkgs.callPackage ./danmaxis/hyprstream-monitors {
    #     inherit (pluginLib) mkNpmOpenDeckPlugin;
    #   };
    # };

    elgato = {
      analogclock = pkgs.callPackage ./elgato/analogclock {
        inherit (pluginLib) mkPrebuiltOpenDeckPlugin;
      };
    };

    havner = {
      uinput-simulation = pkgs.callPackage ./havner/uinput-simulation {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };

    openactionplugins = {
      counter = pkgs.callPackage ./openactionplugins/counter {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };

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

      system = pkgs.callPackage ./openactionplugins/system {
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

    felodeck = {
      obs-tools = pkgs.callPackage ./felodeck/obs-tools {
        inherit (pluginLib) mkRustOpenDeckPlugin;
      };
    };
  };
in
pkgs.lib.mapAttrs (
  _: ownerPlugins:
  pkgs.lib.filterAttrs (
    _: plugin: pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform plugin
  ) ownerPlugins
) plugins
