{ defaultPackage }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.opendeck;

  pluginsWithIds = lib.filter (plugin: plugin ? pluginId) cfg.plugins;
  pluginIds = map (plugin: plugin.pluginId) pluginsWithIds;

  duplicatePluginIds = lib.filter (pluginId: lib.count (id: id == pluginId) pluginIds > 1) (
    lib.unique pluginIds
  );

  bundledPluginIds = cfg.package.bundledPluginIds or [ ];

  bundledPluginConflicts = lib.filter (pluginId: lib.elem pluginId bundledPluginIds) pluginIds;
  externalPlugins = lib.filter (plugin: !(lib.elem plugin.pluginId bundledPluginIds)) pluginsWithIds;

  desiredState = lib.concatMapStrings (plugin: "${plugin.pluginId}\n") externalPlugins;

  # OpenDeck uses Tauri's application config directory on each platform.
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/opendeck"
    else
      "${config.xdg.configHome}/opendeck";

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

    # Repeated activations should not reload unchanged plugin store paths.
    if [[ ! -L "$target" || "$(readlink "$target")" != "$source" ]]; then
      rm -f "$temp"

      # Declarative plugins live in the Nix store; only a symlink is placed
      # in OpenDeck's mutable plugin directory.
      ln -s "$source" "$temp"

      # Preflight validation guarantees that an existing target is a
      # Home Manager-managed symlink. Replace it atomically.
      ${lib.getExe' pkgs.coreutils "mv"} -Tf "$temp" "$target"
      changedPlugins+=("$pluginId")
    fi
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
        changedPlugins=()

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
              changedPlugins+=("$pluginId")
            fi
          done <<<"$previousState"
        fi

        ${installPlugins}

        ${lib.getExe' pkgs.coreutils "mv"} -Tf "$stateTemp" "$externallyManagedPluginsFile"

        # Reconcile every symlink first, then notify one running instance.
        # Never start OpenDeck during Home Manager activation.
        ${lib.optionalString (cfg.reloadOnPluginChanges || cfg.restartOnPluginChanges) ''
          if (( ''${#changedPlugins[@]} )); then
            notify=true
            ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
              # Do not launch a secondary Tauri process unless OpenDeck
              # owns its single-instance D-Bus name.
              # Upstream explicitly sets this ID via .dbus_id() in main.rs.
              notify=false
              if ${lib.getExe' pkgs.glib "gdbus"} call --session \
                --dest org.freedesktop.DBus \
                --object-path /org/freedesktop/DBus \
                --method org.freedesktop.DBus.NameHasOwner \
                me.amankhanna.opendeck.SingleInstance 2>/dev/null | grep -Fq '(true,)'; then
                notify=true
              fi
            ''}
            if [[ "$notify" == true ]]; then
              ${
                if cfg.restartOnPluginChanges then
                  ''
                    ${cfg.package}/bin/opendeck --restart-if-running >/dev/null 2>&1 \
                      || verboseEcho "Could not restart OpenDeck; plugin changes will apply next time it starts"
                  ''
                else
                  ''
                    for pluginId in "''${changedPlugins[@]}"; do
                      ${cfg.package}/bin/opendeck --reload-plugin "$pluginId" >/dev/null 2>&1 \
                        || verboseEcho "Could not reload OpenDeck plugin $pluginId; restart OpenDeck to apply the change"
                    done
                  ''
              }
            fi
          fi
        ''}
      fi
    '';
  };
}
