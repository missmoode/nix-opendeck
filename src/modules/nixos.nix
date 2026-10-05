{ defaultPackage }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.hardware.opendeck;
in
{
  options.hardware.opendeck.enable = lib.mkEnableOption "hardware access required by OpenDeck";

  config = lib.mkIf cfg.enable {
    services.udev.packages = [
      defaultPackage
    ];
  };
}
