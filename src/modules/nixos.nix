{ defaultUdevPackages }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.hardware.opendeck;
in
{
  options.hardware.opendeck = {
    enable = lib.mkEnableOption "hardware access required by OpenDeck";

    udevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = defaultUdevPackages;
      description = "Packages providing udev rules required by OpenDeck and its plugins.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = cfg.udevPackages;
  };
}
