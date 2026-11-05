{
  pkgs,
  support,
}:

let
  inherit (support) mkActivation mkPlugin managedId;
  old = mkPlugin managedId "old";
  new = mkPlugin managedId "new";

  # A single production activation entry decides between restart and reload.
  combinedReload = mkActivation {
    plugins = [ old ];
    settings = {
      brightness = 75;
      future_toggle = true;
    };
  };
  settingsRestart = mkActivation {
    plugins = [ old ];
    settings.brightness = 75;
    restartOnSettingsChanges = true;
  };
  upgradedWithSettingsRestart = mkActivation {
    plugins = [ new ];
    settings.brightness = 75;
    restartOnSettingsChanges = true;
  };
  bothRestarts = mkActivation {
    plugins = [ old ];
    settings.brightness = 75;
    restartOnPluginChanges = true;
    restartOnSettingsChanges = true;
  };
  pluginRestart = mkActivation {
    plugins = [ old ];
    restartOnPluginChanges = true;
  };
  settingsOnlyRestart = mkActivation {
    settings.brightness = 75;
    reloadOnPluginChanges = false;
    restartOnSettingsChanges = true;
  };
  disabled = mkActivation {
    plugins = [ old ];
    settings.brightness = 75;
    reloadOnPluginChanges = false;
  };
  removed = mkActivation {
    plugins = [ ];
    reloadOnPluginChanges = true;
  };
in
pkgs.runCommand "opendeck-home-manager-activation-notifications"
  { inherit (support) nativeBuildInputs; }
  ''
    ${support.setup}

    render ${combinedReload} "$root/reload.sh"
    render ${settingsRestart} "$root/settings-restart.sh"
    render ${upgradedWithSettingsRestart} "$root/upgraded-settings-restart.sh"
    render ${bothRestarts} "$root/both-restarts.sh"
    render ${pluginRestart} "$root/plugin-restart.sh"
    render ${settingsOnlyRestart} "$root/settings-only-restart.sh"
    render ${disabled} "$root/disabled.sh"
    render ${removed} "$root/removed.sh"

    ${support.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      if ! grep -Fq "$root/mock-gdbus" "$root/reload.sh"; then
        echo "OpenDeck D-Bus mock was not injected into the notification script" >&2
        exit 1
      fi
    ''}

    # Dry runs should never create state files, change symlinks or notify.
    DRY_RUN=1 bash "$root/both-restarts.sh"
    [[ ! -e "$state" && ! -e "$settingsFile" ]]
    expect_commands ""

    # Default: reload new plugin, but do not restart for settings changes.
    bash "$root/reload.sh"
    expect_commands "--reload-plugin ${managedId}"
    jq -e '.brightness == 75 and .future_toggle == true' "$settingsFile" >/dev/null
    rm -f "$OPENDECK_TEST_LOG"
    bash "$root/reload.sh"
    expect_commands ""

    # Settings changes restart exactly once even when plugin reload is enabled.
    jq '.brightness = 20' "$settingsFile" > "$root/edited-settings.json"
    mv "$root/edited-settings.json" "$settingsFile"
    bash "$root/settings-restart.sh"
    expect_commands "--restart-if-running"
    rm -f "$OPENDECK_TEST_LOG"
    bash "$root/settings-restart.sh"
    expect_commands ""

    # A plugin-only upgrade with unchanged settings still reloads normally.
    bash "$root/upgraded-settings-restart.sh"
    expect_commands "--reload-plugin ${managedId}"
    rm -f "$OPENDECK_TEST_LOG"
    bash "$root/upgraded-settings-restart.sh"
    expect_commands ""

    reset_state
    bash "$root/both-restarts.sh"
    expect_commands "--restart-if-running"
    rm -f "$OPENDECK_TEST_LOG"
    bash "$root/both-restarts.sh"
    expect_commands ""

    reset_state
    bash "$root/plugin-restart.sh"
    expect_commands "--restart-if-running"

    reset_state
    bash "$root/settings-only-restart.sh"
    expect_commands "--restart-if-running"

    reset_state
    bash "$root/disabled.sh"
    expect_commands ""

    # Removing a previously managed plugin is also a reload-worthy change.
    bash "$root/removed.sh"
    expect_commands "--reload-plugin ${managedId}"

    # No Linux D-Bus owner: do not call the launcher or start a GUI.
    ${support.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      reset_state
      OPENDECK_TEST_DBUS=false bash "$root/both-restarts.sh"
      expect_commands ""
    ''}

    touch "$out"
  ''
