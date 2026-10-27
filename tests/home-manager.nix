{
  lib,
  pkgs,
  homeManager,
  module,
  opendeck,
  core,
  starterpack,
}:

let
  mkConfiguration =
    settings:
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        module
        {
          home.username = "test";
          home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test" else "/home/test";
          home.stateVersion = "26.05";

          programs.opendeck = settings;
        }
      ];
    };

  disabled = mkConfiguration {
    enable = false;
  };

  defaultEnabled = mkConfiguration {
    enable = true;
  };

  pluginsOnly = mkConfiguration {
    enable = true;
    installPackage = false;
    package = core;
    plugins = [ starterpack ];
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

  reloadDisabled = mkConfiguration {
    enable = true;
    installPackage = false;
    package = core;
    plugins = [ starterpack ];
    reloadOnPluginChanges = false;
  };

  restartEnabled = mkConfiguration {
    enable = true;
    installPackage = false;
    package = core;
    plugins = [ starterpack ];
    restartOnPluginChanges = true;
  };

  evaluationFails = configuration: !(builtins.tryEval configuration.config.home.packages).success;

  activationScript = pluginsOnly.config.home.activation.opendeckPlugins.data;

in

assert lib.assertMsg (
  !(disabled.config.home.activation ? opendeckPlugins)
) "Disabled OpenDeck module should not add activation steps";

assert lib.assertMsg (builtins.any (
  p: p.outPath == opendeck.outPath
) defaultEnabled.config.home.packages) "Enabled OpenDeck module should install its default package";

assert lib.assertMsg (
  !builtins.any (package: package.outPath == core.outPath) pluginsOnly.config.home.packages
) "installPackage=false should not install OpenDeck";

assert lib.assertMsg (lib.hasInfix starterpack.pluginId activationScript)
  "Declared plugin ID should appear in the activation script";

assert lib.assertMsg (lib.hasInfix "externally-managed-plugins" activationScript)
  "Activation should maintain the plugin ownership state";

assert lib.assertMsg (evaluationFails bundledConflict)
  "Bundled plugin conflicts should fail Home Manager evaluation";

assert lib.assertMsg (evaluationFails duplicatePlugins)
  "Duplicate plugin IDs should fail Home Manager evaluation";

assert lib.assertMsg (lib.hasInfix "--reload-plugin" activationScript)
  "Automatic reload should be enabled by default";

assert lib.assertMsg (
  !lib.hasInfix "--restart-if-running" activationScript
) "Restart logic should be absent when disabled";

assert lib.assertMsg (
  !lib.hasInfix "--reload-plugin" reloadDisabled.config.home.activation.opendeckPlugins.data
) "Reload logic should be absent when disabled";

assert lib.assertMsg (
  !lib.hasInfix "--restart-if-running" reloadDisabled.config.home.activation.opendeckPlugins.data
) "Disabling reload should not enable restart";

assert lib.assertMsg
  (lib.hasInfix "--restart-if-running" restartEnabled.config.home.activation.opendeckPlugins.data)
  "Restart logic should be present when enabled";

assert lib.assertMsg (
  !lib.hasInfix "--reload-plugin" restartEnabled.config.home.activation.opendeckPlugins.data
) "Restart should take precedence over reload";

# very unlikely for this to fail unless I do something very silly,
# but it's cheap so why not include it.
assert lib.assertMsg (
  !builtins.any (package: package.outPath == opendeck.outPath) disabled.config.home.packages
) "Disabled OpenDeck module should not install OpenDeck";

pkgs.runCommand "opendeck-home-manager-evaluation" { } ''
  touch "$out"
''
