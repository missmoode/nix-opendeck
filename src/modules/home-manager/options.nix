{ defaultPackage }:
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.opendeck;

  pluginsWithIds = lib.filter (plugin: plugin ? pluginId) cfg.plugins;
  pluginIds = map (plugin: plugin.pluginId) pluginsWithIds;
  duplicatePluginIds = lib.filter (id: lib.count (other: other == id) pluginIds > 1) (
    lib.unique pluginIds
  );

  bundledPluginIds = cfg.package.bundledPluginIds or [ ];
  bundledPluginConflicts = lib.filter (id: lib.elem id bundledPluginIds) pluginIds;
in
{
  options.programs.opendeck = {
    enable = lib.mkEnableOption "OpenDeck";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The OpenDeck package to install.";
    };

    installPackage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether or not this module should install OpenDeck for convenience.";
    };

    reloadOnPluginChanges = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reload individual declared plugins when Home Manager changes their
        symlinks, without starting an inactive OpenDeck instance. Disable this
        to apply changes only on the next normal launch. Ignored when
        restartOnPluginChanges is enabled.
      '';
    };

    restartOnPluginChanges = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Restart an already-running OpenDeck instance once after Home Manager
        adds, removes, or changes declared plugins, instead of reloading them
        individually. Takes precedence over reloadOnPluginChanges.
      '';
    };

    restartOnSettingsChanges = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Restart an already-running OpenDeck instance if Home Manager changes
        managed settings. Does not start OpenDeck if it is not running.
        When disabled, changes apply on the next normal launch.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        OpenDeck plugins to install declaratively.
        Each package must provide a pluginId passthru attribute and contain
        the corresponding .sdPlugin directory in its output.

        Plugins declared here are managed by Home Manager and should not also
        be installed or updated through OpenDeck's graphical plugin store.
        Plugins with other IDs may still be installed normally through OpenDeck.

        Runtime requirements declared by plugin packages are not checked by
        this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.length pluginsWithIds == lib.length cfg.plugins;
        message = ''
          programs.opendeck.plugins contains packages without a pluginId
          passthru attribute. Each declared plugin must provide pluginId.
        '';
      }
      {
        assertion = duplicatePluginIds == [ ];
        message = ''
          programs.opendeck.plugins contains duplicate plugin IDs:
          ${lib.concatStringsSep ", " duplicatePluginIds}
        '';
      }
      {
        assertion = bundledPluginConflicts == [ ];
        message = ''
          programs.opendeck.plugins contains plugins already bundled by
          ${cfg.package.pname or "the selected OpenDeck package"}:
          ${lib.concatStringsSep ", " bundledPluginConflicts}

          Remove those plugins from programs.opendeck.plugins, or use
          opendeck-core instead of a package that bundles them.
        '';
      }
    ];

    home.packages = lib.optional cfg.installPackage cfg.package;
  };
}
