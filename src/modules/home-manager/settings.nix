{ lib, ... }:
{
  options.programs.opendeck.settings = lib.mkOption {
    default = { };
    description = ''
      OpenDeck settings to apply at Home Manager activation. Only non-null
      values are managed; other fields in settings.json remain untouched.
      Undeclared JSON-compatible keys are accepted for future upstream
      settings, but are not individually checked against OpenDeck's schema.
      A running OpenDeck may overwrite external changes until restarted.
    '';
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.json;
      options = {
        language = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Interface language.";
        };
        brightness = lib.mkOption {
          type = lib.types.nullOr (lib.types.ints.between 0 100);
          default = null;
          description = "Device brightness (0–100).";
        };
        sleep_timeout_minutes = lib.mkOption {
          type = lib.types.nullOr (lib.types.ints.between 0 65535);
          default = null;
          description = "Minutes of inactivity before device sleep (0 disables).";
        };
        sleep_when_computer_locked = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Sleep devices when the computer is locked.";
        };
        rotation = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              0
              90
              180
              270
            ]
          );
          default = null;
          description = "Device rotation in degrees.";
        };
        background = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Keep OpenDeck running in the background.";
        };
        autolaunch = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable OpenDeck's own autostart behavior.";
        };
        updatecheck = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable OpenDeck's upstream update checks.";
        };
        statistics = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable anonymous usage statistics.";
        };
        separatewine = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Use a separate Wine prefix per plugin.";
        };
        developer = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable OpenDeck developer features.";
        };
        disableelgato = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Disable built-in Elgato device discovery.";
        };
      };
    };
  };
}
