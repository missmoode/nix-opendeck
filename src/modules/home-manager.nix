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

  requiredCommands = lib.concatMap (
    plugin:
    map (requirement: {
      inherit requirement;
      pluginId = plugin.pluginId;
    }) (plugin.requiredCommands or [ ])
  ) cfg.plugins;

  installPlugins = lib.concatMapStringsSep "\n" (plugin: ''
    pluginId=${lib.escapeShellArg plugin.pluginId}
    source=${lib.escapeShellArg "${plugin}/${plugin.pluginId}"}
    target="$pluginDir/$pluginId"
    temp="$pluginDir/.$pluginId.hm-tmp"

    if [[ ! -d "$source" ]]; then
      echo "error: OpenDeck plugin '$pluginId' does not contain '$pluginId'" >&2
      exit 1
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      if ! grep -Fqx -- "$pluginId" <<<"$previousState"; then
        echo "warning: OpenDeck plugin '$pluginId' is already installed but is not managed by Home Manager." >&2
        echo "warning: Remove the existing plugin before declaring '$pluginId' in Home Manager." >&2
        continue
      fi
    fi

    rm -f "$temp"

    # Declarative plugins live in the Nix store; only a symlink is placed
    # in OpenDeck's mutable plugin directory.
    ln -s "$source" "$temp"

    # At this point an existing target is known to be Home Manager-owned.
    rm -rf "$target"
    mv "$temp" "$target"

    installedPluginIds+="$pluginId"$'\n'
  '') externalPlugins;
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
    ];

    home.activation.opendeckrequiredCommands = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      missing=0

      ${lib.concatMapStringsSep "\n" (
        { pluginId, requirement }:
        ''
          if ! command -v ${lib.escapeShellArg requirement} >/dev/null 2>&1; then
            echo "error: OpenDeck plugin '${lib.escapeShellArg pluginId}' requires '${lib.escapeShellArg requirement}', but it was not found in PATH." >&2
            echo "error: Provide '${lib.escapeShellArg requirement}' through your system or another package manager before enabling this plugin." >&2
            missing=1
          fi
        ''
      ) requiredCommands}

      if (( missing )); then
        exit 1
      fi
    '';

    home.activation.opendeckPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configDir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      pluginDir="$configDir/opendeck/plugins"
      stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/opendeck"
      stateFile="$stateDir/home-manager-plugins"

      if [[ -n "''${DRY_RUN:-}" ]]; then
        verboseEcho "Would update Home Manager managed OpenDeck plugins"
      else
        mkdir -p "$pluginDir" "$stateDir"

        previousState=""
        if [[ -f "$stateFile" ]]; then
          previousState=$(cat "$stateFile")
        fi

        installedPluginIds=""

        # Remove plugins that were managed by the previous Home Manager
        # generation but are no longer declared.
        #
        # Only remove a symlink which still points into the Nix store.
        # This prevents stale state from deleting a manually installed
        # graphical plugin with the same ID.
        if [[ -n "$previousState" ]]; then
          while IFS= read -r pluginId; do
            [[ -n "$pluginId" ]] || continue

            target="$pluginDir/$pluginId"

            if [[ -L "$target" ]]; then
              targetPath=$(readlink -f "$target" 2>/dev/null || true)

              if [[ "$targetPath" == /nix/store/* ]]; then
                rm -f "$target"
              fi
            fi
          done <<<"$previousState"
        fi

        ${installPlugins}

        printf '%s' "$installedPluginIds" > "$stateFile"
      fi
    '';
  };
}
