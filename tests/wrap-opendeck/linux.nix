{
  pkgs,
  fixtures,
}:

let
  inherit (fixtures)
    plugin
    pluginId
    wrapped
    ;

in

pkgs.runCommand "opendeck-wrap-linux" { } ''
  set -euo pipefail

  # Wrapping must preserve resources from opendeck-core.
  test -f "${wrapped}/share/opendeck/core-marker"

  # The launcher must receive the bundled plugins directory.
  bundle="$("${wrapped}/bin/opendeck")"
  test -n "$bundle"

  # Plugins should be linked rather than copied.
  test -L "$bundle/${pluginId}"
  test "$(readlink "$bundle/${pluginId}")" = \
    "${plugin}/${pluginId}"

  # The linked plugin must remain accessible.
  test -f "$bundle/${pluginId}/manifest.json"

  # Bundled plugin udev rules should be propagated.
  test -f \
    "${wrapped.udev}/lib/udev/rules.d/99-opendeck-wrap-test.rules"

  touch "$out"
''
