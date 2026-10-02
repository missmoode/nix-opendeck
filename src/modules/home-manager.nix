{ defaultPackage }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.opendeck;

  pluginIds = map (plugin: plugin.pluginId) cfg.plugins;

  duplicatePluginIds = lib.filter (pluginId: lib.count (id: id == pluginId) pluginIds > 1) (
    lib.unique pluginIds
  );

  bundledPluginIds = cfg.package.bundledPluginIds or [ ];

  bundledPluginConflicts = lib.filter (pluginId: lib.elem pluginId bundledPluginIds) pluginIds;

  externalPlugins = lib.filter (plugin: !(lib.elem plugin.pluginId bundledPluginIds)) cfg.plugins;

  externalPluginIds = map (plugin: plugin.pluginId) externalPlugins;

  runtimePackages = lib.unique (lib.concatMap (plugin: plugin.runtimePackages or [ ]) cfg.plugins);

  installPlugins = lib.concatMapStringsSep "\n" (plugin: ''
    pluginId=${lib.escapeShellArg plugin.pluginId}
    source=${lib.escapeShellArg "${plugin}/${plugin.pluginId}"}
    target="$pluginDir/$pluginId"
    temp="$pluginDir/.$pluginId.hm-tmp"

    rm -rf "$temp"
    cp -r "$source" "$temp"
    chmod -R u+rwX "$temp"
    rm -rf "$target"
    mv "$temp" "$target"
  '') externalPlugins;

  pluginIdList = lib.concatStringsSep "\n" externalPluginIds;
in
{
  options.programs.opendeck = {
    enable = lib.mkEnableOption "OpenDeck";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The OpenDeck package to install.";
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
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
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

    home.packages = [
      cfg.package
    ]
    ++ runtimePackages;

    home.activation.opendeckPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              configDir="''${XDG_CONFIG_HOME:-$HOME/.config}"
              pluginDir="$configDir/opendeck/plugins"

              stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/opendeck"
              stateFile="$stateDir/home-manager-plugins"

              if [[ -n "''${DRY_RUN:-}" ]]; then
                verboseEcho "Would update Home Manager managed OpenDeck plugins"
              else
                mkdir -p "$pluginDir" "$stateDir"

                # Remove plugins managed by the previous Home Manager generation.
                if [[ -f "$stateFile" ]]; then
                  while IFS= read -r pluginId; do
                    [[ -n "$pluginId" ]] || continue
                    rm -rf "$pluginDir/$pluginId"
                  done < "$stateFile"
                fi

                ${installPlugins}

                cat > "$stateFile" <<'EOF'
      ${pluginIdList}
      EOF
              fi
    '';
  };
}
