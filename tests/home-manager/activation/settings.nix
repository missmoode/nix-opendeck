{
  pkgs,
  support,
}:

let
  inherit (support) mkActivation mkPlugin managedId;
  settingsScript = mkActivation {
    settings = {
      brightness = 75;
      updatecheck = false;
      sleep_timeout_minutes = 0;
      future_values = [
        0
        "new"
        false
      ];
      future_object = {
        enabled = true;
      };
    };
    reloadOnPluginChanges = false;
  };
  # Test that invalid settings cannot leave plugin symlinks partially changed.
  withPlugin = mkActivation {
    plugins = [ (mkPlugin managedId "preflight") ];
    settings.brightness = 75;
    reloadOnPluginChanges = false;
  };
in
pkgs.runCommand "opendeck-home-manager-activation-settings" { inherit (support) nativeBuildInputs; }
  ''
    ${support.setup}

    render ${settingsScript} "$root/settings.sh"
    render ${withPlugin} "$root/settings-with-plugin.sh"

    DRY_RUN=1 bash "$root/settings.sh"
    [[ ! -e "$settingsFile" && ! -e "$state" ]]

    bash "$root/settings.sh"
    jq -e '.brightness == 75 and .updatecheck == false and .sleep_timeout_minutes == 0
      and .future_values == [0,"new",false] and .future_object.enabled == true' \
      "$settingsFile" >/dev/null
    cp "$settingsFile" "$root/expected.json"
    bash "$root/settings.sh"
    cmp -s "$root/expected.json" "$settingsFile"

    # Preserve unrelated user settings and future keys.
    printf '%s\n' '{"brightness":10,"updatecheck":true,"language":"fr","extra":{"keep":true}}' > "$settingsFile"
    bash "$root/settings.sh"
    jq -e '.brightness == 75 and .updatecheck == false and .language == "fr"
      and .extra.keep == true and .future_values == [0,"new",false]' \
      "$settingsFile" >/dev/null

    # No Home Manager EXIT-trap override, including when sourced.
    cat > "$root/outer-trap.sh" <<END_TRAP_TEST
    set -euo pipefail
    trap 'printf "%s\\n" preserved > "$root/outer-trap-ran"' EXIT
    source "$root/settings.sh"
    END_TRAP_TEST
    bash "$root/outer-trap.sh"
    [[ "$(cat "$root/outer-trap-ran")" == preserved ]]

    printf '%s\n' '{malformed JSON' > "$settingsFile"
    cp "$settingsFile" "$root/invalid-original"
    expect_failure "$root/settings-with-plugin.sh"
    cmp -s "$root/invalid-original" "$settingsFile"
    [[ ! -L "$pluginDir/${managedId}" && ! -e "$pluginDir/${managedId}" ]]
    # Settings preflight must precede *any* plugin state modification.
    [[ -f "$state" && ! -s "$state" ]]

    printf '%s\n' '[]' > "$settingsFile"
    expect_failure "$root/settings.sh"
    [[ "$(cat "$settingsFile")" == '[]' ]]

    # Multiple JSON documents are not one valid settings object.
    printf '%s\n' '{}' '{}' > "$settingsFile"
    expect_failure "$root/settings.sh"

    rm "$settingsFile"
    printf '%s\n' '{"language":"fr"}' > "$root/user-settings.json"
    ln -s "$root/user-settings.json" "$settingsFile"
    expect_failure "$root/settings.sh"
    [[ -L "$settingsFile" && "$(cat "$root/user-settings.json")" == '{"language":"fr"}' ]]
    rm "$settingsFile"
    ln -s "$root/nonexistent.json" "$settingsFile"
    expect_failure "$root/settings.sh"
    [[ -L "$settingsFile" ]]

    expect_commands ""
    touch "$out"
  ''
