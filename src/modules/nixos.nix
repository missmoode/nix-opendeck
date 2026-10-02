{ defaultPackage }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.opendeck;
in
{
  options.programs.opendeck = {
    enable = lib.mkEnableOption "OpenDeck";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The OpenDeck package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];

    services.udev.packages = [
      cfg.package
    ];
  };
}
