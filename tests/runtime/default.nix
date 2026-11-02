{ pkgs }:

let
  inherit (pkgs) lib;
  linux = pkgs.stdenv.hostPlatform.isLinux;
  unrelatedAsset = pkgs.writeText "opendeck-runtime-unrelated.svg" "<svg>forbidden store asset</svg>\n";
in
pkgs.writeShellApplication {
  name = "opendeck-runtime-test";

  runtimeInputs = [ pkgs.python3 ] ++ lib.optionals linux [
    pkgs.dbus
    pkgs.glib
    pkgs.xvfb-run
  ];

  text = ''
    export OPENDECK_TEST_UNRELATED_ASSET=${unrelatedAsset}
    ${if linux then ''
      # The private bus activates portals using its inherited environment.
      # Do not let them attach to the caller's real Wayland/Hyprland session.
      unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
      export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11

      # Start the bus after Xvfb so activated services see the test display.
      exec xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
        dbus-run-session -- ${pkgs.python3}/bin/python3 ${./.}/run.py "$@"
    '' else ''
      exec ${pkgs.python3}/bin/python3 ${./.}/run.py "$@"
    ''}
  '';
}
