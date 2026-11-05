{
  pkgs,
  homeManager,
  module,
}:

let
  support = import ./support.nix { inherit pkgs homeManager module; };
  plugins = import ./plugins.nix { inherit pkgs support; };
  settings = import ./settings.nix { inherit pkgs support; };
  notifications = import ./notifications.nix { inherit pkgs support; };
in
{
  home-manager-activation-plugins = plugins;
  home-manager-activation-settings = settings;
  home-manager-activation-notifications = notifications;

  # Preserve the historical check name while making its constituent tests
  # independently runnable during development.
  home-manager-activation = pkgs.runCommand "opendeck-home-manager-activation" { } ''
    test -e ${plugins}
    test -e ${settings}
    test -e ${notifications}
    touch "$out"
  '';
}
