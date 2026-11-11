{
  lib,
  pkgs,
  homeManager,
  module,
  opendeck,
  core,
  starterpack,
  traditionalModule,
  traditionalOpendeck,
}:

let
  mkConfigurationWith =
    selectedModule: options:
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        selectedModule
        {
          home.username = "test";
          home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test" else "/home/test";
          home.stateVersion = "26.05";
          programs.opendeck = options;
        }
      ];
    };

  mkConfiguration = mkConfigurationWith module;

  traditionalEnabled = mkConfigurationWith traditionalModule {
    enable = true;
  };

  disabled = mkConfiguration { enable = false; };
  enabled = mkConfiguration { enable = true; };
  pluginsOnly = mkConfiguration {
    enable = true;
    installPackage = false;
    package = core;
    plugins = [ starterpack ];
  };
  noNotifications = mkConfiguration {
    enable = true;
    reloadOnPluginChanges = false;
  };
  pluginRestart = mkConfiguration {
    enable = true;
    restartOnPluginChanges = true;
  };
  settingsRestart = mkConfiguration {
    enable = true;
    settings.updatecheck = false;
    restartOnSettingsChanges = true;
  };
  managedSettings = mkConfiguration {
    enable = true;
    settings = {
      brightness = 75;
      updatecheck = false;
      sleep_timeout_minutes = 0;
      rotation = 90;
      future_toggle = true;
      future_values = [
        0
        "example"
        false
      ];
      future_object = {
        enabled = true;
      };
    };
  };
  nullSettings = mkConfiguration {
    enable = true;
    settings = {
      updatecheck = null;
      future_toggle = null;
    };
  };

  bundledConflict = mkConfiguration {
    enable = true;
    plugins = [ starterpack ];
  };
  duplicatePlugins = mkConfiguration {
    enable = true;
    package = core;
    plugins = [
      starterpack
      starterpack
    ];
  };
  missingPluginId = mkConfiguration {
    enable = true;
    plugins = [ pkgs.hello ];
  };
  invalidBrightness = mkConfiguration {
    enable = true;
    settings.brightness = "bright";
  };
  invalidRotation = mkConfiguration {
    enable = true;
    settings.rotation = 45;
  };
  invalidFutureValue = mkConfiguration {
    enable = true;
    settings.future = _: 42;
  };

  # Home Manager checks assertions before exposing the evaluated config.
  # Trying to inspect config.assertions directly would throw instead.
  evaluationFails = configuration: !(builtins.tryEval configuration.config.home.packages).success;
  settingsEvaluationFails =
    configuration:
    !(builtins.tryEval (builtins.deepSeq configuration.config.home.activation.opendeck.data true))
    .success;

  activation = pluginsOnly.config.home.activation.opendeck.data;
  settingsActivation = managedSettings.config.home.activation.opendeck.data;
  noNotificationActivation = noNotifications.config.home.activation.opendeck.data;
in
assert lib.assertMsg (
  !(disabled.config.home.activation ? opendeck)
) "Disabled OpenDeck module should not create an activation entry";

assert lib.assertMsg (builtins.any (
  p: p.outPath == opendeck.outPath
) enabled.config.home.packages) "Enabled module should install the default package";

assert lib.assertMsg (lib.any (p: p.outPath == traditionalOpendeck.outPath)
  traditionalEnabled.config.home.packages
) "Traditional Home Manager module should install its default package";

assert lib.assertMsg
  (lib.hasInfix "externally-managed-plugins" traditionalEnabled.config.home.activation.opendeck.data)
  "Traditional Home Manager module should provide plugin activation";

assert lib.assertMsg (
  !builtins.any (p: p.outPath == core.outPath) pluginsOnly.config.home.packages
) "installPackage=false should not install OpenDeck";

assert lib.assertMsg (lib.hasInfix starterpack.pluginId activation)
  "Declared plugins should appear in reconciliation";

assert lib.assertMsg (lib.hasInfix "externally-managed-plugins" activation)
  "Activation must maintain plugin ownership state";

assert lib.assertMsg (lib.hasInfix "settings.json" settingsActivation)
  "Managed settings should be reconciled in the same activation";

assert lib.assertMsg (lib.hasInfix ''"brightness":75'' settingsActivation)
  "Known settings should serialize correctly";

assert lib.assertMsg (lib.hasInfix ''"updatecheck":false'' settingsActivation)
  "Explicit false must not be discarded";

assert lib.assertMsg (lib.hasInfix ''"sleep_timeout_minutes":0'' settingsActivation)
  "Explicit zero must not be discarded";

assert lib.assertMsg (lib.hasInfix ''"future_toggle":true'' settingsActivation)
  "Unknown boolean fields should be accepted";

assert lib.assertMsg (lib.hasInfix ''"future_values":[0,"example",false]'' settingsActivation)
  "Unknown list fields should be accepted";

assert lib.assertMsg (lib.hasInfix ''"future_object":{'' settingsActivation)
  "Unknown JSON objects should be accepted";

assert lib.assertMsg (
  !lib.hasInfix ''"autolaunch":'' settingsActivation
) "Unmanaged known settings must not be written";

assert lib.assertMsg (
  !lib.hasInfix "managedSettings=" nullSettings.config.home.activation.opendeck.data
) "Null-only settings should not generate JSON reconciliation";

assert lib.assertMsg (
  !lib.hasInfix "managedSettings=" enabled.config.home.activation.opendeck.data
) "Empty settings should not generate JSON reconciliation";

assert lib.assertMsg (lib.hasInfix "reloadPlugins=true" activation)
  "Plugin reload must remain enabled by default";

assert lib.assertMsg (lib.hasInfix "restartPlugins=false" activation)
  "Plugin restarts must remain disabled by default";

assert lib.assertMsg (lib.hasInfix "restartSettings=false" activation)
  "Settings restarts must be opt-in";

assert lib.assertMsg (
  !lib.hasInfix "isRunning()" noNotificationActivation
) "No notification options should avoid D-Bus probing";

assert lib.assertMsg
  (lib.hasInfix "restartPlugins=true" pluginRestart.config.home.activation.opendeck.data)
  "Plugin restart setting must be propagated";

assert lib.assertMsg
  (lib.hasInfix "restartSettings=true" settingsRestart.config.home.activation.opendeck.data)
  "Settings restart setting must be propagated";

assert lib.assertMsg (evaluationFails bundledConflict)
  "Bundled plugin conflicts should fail validation";

assert lib.assertMsg (evaluationFails duplicatePlugins)
  "Duplicate plugin IDs should fail validation";

assert lib.assertMsg (evaluationFails missingPluginId)
  "Plugins without pluginId must fail validation";

assert lib.assertMsg (settingsEvaluationFails invalidBrightness)
  "Known settings should be type-checked";

assert lib.assertMsg (settingsEvaluationFails invalidRotation)
  "Rotation must be restricted to supported values";

assert lib.assertMsg (settingsEvaluationFails invalidFutureValue)
  "Unknown settings must still be JSON-compatible";

pkgs.runCommand "opendeck-home-manager-evaluation" { } ''
  touch "$out"
''
