{ defaultUdevPackage }:

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

    udevPackage = lib.mkOption {
      type = lib.types.package;
      default = defaultUdevPackage;
      description = "Package providing OpenDeck's core udev rules.";
    };

    extraUdevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages providing udev rules required by OpenDeck plugins.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ cfg.udevPackage ] ++ cfg.extraUdevPackages;
  };
}
