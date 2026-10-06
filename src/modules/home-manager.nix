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

  desiredState = lib.concatMapStrings (plugin: "${plugin.pluginId}\n") externalPlugins;

  # These correspond to OpenDeck's Tauri application config directory on Linux.
  #
  # Keeping them defined here makes the platform-specific path easy to replace
  # if the Home Manager module later gains Darwin support.
  configDir = "${config.xdg.configHome}/opendeck";
  pluginDir = "${configDir}/plugins";
  externallyManagedPluginsFile = "${configDir}/externally-managed-plugins";

  validatePlugins = lib.concatMapStringsSep "\n" (plugin: ''
    pluginId=${lib.escapeShellArg plugin.pluginId}
    source=${lib.escapeShellArg "${plugin}/${plugin.pluginId}"}
    target="$pluginDir/$pluginId"

    if [[ ! -d "$source" ]]; then
      echo "error: OpenDeck plugin '$pluginId' does not contain '$pluginId'" >&2
      validationFailed=1
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      if ! isManagedPluginTarget "$pluginId"; then
        echo "error: OpenDeck plugin '$pluginId' is already installed but is not managed by Home Manager." >&2
        echo "error: Remove the existing plugin before declaring '$pluginId' in Home Manager." >&2
        validationFailed=1
      fi
    fi
  '') externalPlugins;

  installPlugins = lib.concatMapStringsSep "\n" (plugin: ''
    pluginId=${lib.escapeShellArg plugin.pluginId}
    source=${lib.escapeShellArg "${plugin}/${plugin.pluginId}"}
    target="$pluginDir/$pluginId"
    temp="$pluginDir/.$pluginId.hm-tmp"

    rm -f "$temp"

    # Declarative plugins live in the Nix store; only a symlink is placed
    # in OpenDeck's mutable plugin directory.
    ln -s "$source" "$temp"

    # Preflight validation guarantees that an existing target is a
    # Home Manager-managed symlink.
    rm -f "$target"
    mv "$temp" "$target"
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

    installPackage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether or not this module should install OpenDeck for convenience.";
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

    home.activation.opendeckPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configDir=${lib.escapeShellArg configDir}
      pluginDir=${lib.escapeShellArg pluginDir}
      externallyManagedPluginsFile=${lib.escapeShellArg externallyManagedPluginsFile}
      desiredState=${lib.escapeShellArg desiredState}

      if [[ -n "''${DRY_RUN:-}" ]]; then
        verboseEcho "Would update Home Manager managed OpenDeck plugins"
      else
        previousState=""
        if [[ -f "$externallyManagedPluginsFile" ]]; then
          previousState=$(cat "$externallyManagedPluginsFile")
        fi

        # A plugin is considered Home Manager-managed only when both our
        # ownership state and the filesystem agree.
        isManagedPluginTarget() {
          local pluginId="$1"
          local target="$pluginDir/$pluginId"
          local targetPath

          grep -Fqx -- "$pluginId" <<<"$previousState" || return 1
          [[ -L "$target" ]] || return 1

          targetPath=$(readlink -f "$target" 2>/dev/null || true)
          [[ "$targetPath" == /nix/store/* ]]
        }

        # Validate the complete desired state before modifying anything.
        validationFailed=0

        ${validatePlugins}

        if (( validationFailed )); then
          exit 1
        fi

        mkdir -p "$pluginDir"

        # Prepare the new ownership state before changing installed plugins.
        # The existing state remains authoritative until reconciliation
        # completes successfully.
        stateTemp="$externallyManagedPluginsFile.hm-tmp"
        rm -f "$stateTemp"
        printf '%s' "$desiredState" > "$stateTemp"

        # Remove plugins which were managed by the previous Home Manager
        # generation but are no longer declared.
        #
        # Only remove targets which are still recognisably Home Manager-owned.
        if [[ -n "$previousState" ]]; then
          while IFS= read -r pluginId; do
            [[ -n "$pluginId" ]] || continue

            if grep -Fqx -- "$pluginId" <<<"$desiredState"; then
              continue
            fi

            if isManagedPluginTarget "$pluginId"; then
              rm -f "$pluginDir/$pluginId"
            fi
          done <<<"$previousState"
        fi

        ${installPlugins}

        mv "$stateTemp" "$externallyManagedPluginsFile"
      fi
    '';
  };
}
