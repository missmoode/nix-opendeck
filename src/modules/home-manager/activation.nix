{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.opendeck;

  pluginsWithIds = lib.filter (plugin: plugin ? pluginId) cfg.plugins;
  bundledPluginIds = cfg.package.bundledPluginIds or [ ];
  externalPlugins = lib.filter (plugin: !(lib.elem plugin.pluginId bundledPluginIds)) pluginsWithIds;
  desiredState = lib.concatMapStrings (plugin: "${plugin.pluginId}\n") externalPlugins;

  # OpenDeck uses Tauri's application config directory on each platform.
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/opendeck"
    else
      "${config.xdg.configHome}/opendeck";

  pluginDir = "${configDir}/plugins";
  ownershipFile = "${configDir}/externally-managed-plugins";

  managedSettings = lib.filterAttrs (_: value: value != null) cfg.settings;
  hasManagedSettings = managedSettings != { };
  jq = lib.getExe pkgs.jq;
  mv = lib.getExe' pkgs.coreutils "mv";

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

    if [[ ! -L "$target" || "$(readlink "$target")" != "$source" ]]; then
      rm -f "$temp"
      ln -s "$source" "$temp"
      # Validated Home Manager-owned symlinks are safe to replace atomically.
      ${mv} -Tf "$temp" "$target"
      changedPlugins+=("$pluginId")
    fi
  '') externalPlugins;

  notificationsEnabled =
    cfg.reloadOnPluginChanges || cfg.restartOnPluginChanges || cfg.restartOnSettingsChanges;
in
{
  config = lib.mkIf cfg.enable {
    # One entry owns the entire reconciliation and notification lifecycle.
    # A subshell isolates variables and the EXIT trap from Home Manager.
    home.activation.opendeck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -n "''${DRY_RUN:-}" ]]; then
        verboseEcho "Would reconcile Home Manager managed OpenDeck plugins and settings"
      else
        (
          set -euo pipefail

          configDir=${lib.escapeShellArg configDir}
          pluginDir=${lib.escapeShellArg pluginDir}
          ownershipFile=${lib.escapeShellArg ownershipFile}
          settingsFile="$configDir/settings.json"
          desiredState=${lib.escapeShellArg desiredState}
          changedPlugins=()
          settingsChanged=false
          stateTemp=""
          settingsTemp=""

          cleanup() {
            if [[ -n "$stateTemp" ]]; then rm -f "$stateTemp"; fi
            if [[ -n "$settingsTemp" ]]; then rm -f "$settingsTemp"; fi
          }
          trap cleanup EXIT

          previousState=""
          if [[ -f "$ownershipFile" ]]; then
            previousState=$(cat "$ownershipFile")
          fi

          # Ownership must be recorded and the target must still be a store
          # symlink. Ordinary user-installed plugins are never overwritten.
          isManagedPluginTarget() {
            local pluginId="$1"
            local target="$pluginDir/$pluginId"
            local resolved

            grep -Fqx -- "$pluginId" <<<"$previousState" || return 1
            [[ -L "$target" ]] || return 1
            resolved=$(readlink -f "$target" 2>/dev/null || true)
            [[ "$resolved" == /nix/store/* ]]
          }

          # Preflight before modifying any plugin targets or ownership state.
          validationFailed=0
          ${validatePlugins}
          if (( validationFailed )); then
            exit 1
          fi

          ${lib.optionalString hasManagedSettings ''
            # A symlink (including a dangling one) belongs to another manager.
            if [[ -L "$settingsFile" ]]; then
              echo "error: OpenDeck settings.json is a symlink; refusing to replace it" >&2
              exit 1
            fi
            if [[ -e "$settingsFile" ]]; then
              if [[ ! -f "$settingsFile" ]] || ! ${jq} -s -e 'length == 1 and (.[0] | type == "object")' "$settingsFile" >/dev/null; then
                echo "error: OpenDeck settings.json is not a valid JSON object" >&2
                exit 1
              fi
            fi
          ''}

          # Prepare and compare the new settings *before* plugin mutations.
          # This also prevents a jq failure from leaving plugins half-updated.
          ${lib.optionalString hasManagedSettings ''
            mkdir -p "$configDir"
            managedSettings=${lib.escapeShellArg (builtins.toJSON managedSettings)}
            settingsTemp=$(mktemp "$configDir/.settings.json.hm.XXXXXX")
            if [[ -f "$settingsFile" ]]; then
              printf '%s\n' "$managedSettings" | ${jq} -s '.[0] * .[1]' "$settingsFile" - > "$settingsTemp"
              if ! ${jq} -s -e '.[0] == .[1]' "$settingsFile" "$settingsTemp" >/dev/null; then
                settingsChanged=true
              fi
            else
              printf '%s\n' "$managedSettings" > "$settingsTemp"
              settingsChanged=true
            fi
          ''}

          mkdir -p "$pluginDir"
          stateTemp=$(mktemp "$configDir/.externally-managed-plugins.hm.XXXXXX")
          printf '%s' "$desiredState" > "$stateTemp"

          # Remove only symlinks still recognisably owned by Home Manager.
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

          if cmp -s "$stateTemp" "$ownershipFile"; then
            rm -f "$stateTemp"
          else
            ${mv} -Tf "$stateTemp" "$ownershipFile"
          fi
          stateTemp=""

          ${lib.optionalString hasManagedSettings ''
            if [[ "$settingsChanged" == true ]]; then
              mv -f "$settingsTemp" "$settingsFile"
            else
              rm -f "$settingsTemp"
            fi
            settingsTemp=""
          ''}

          ${lib.optionalString notificationsEnabled ''
            restartPlugins=${lib.boolToString cfg.restartOnPluginChanges}
            restartSettings=${lib.boolToString cfg.restartOnSettingsChanges}
            reloadPlugins=${lib.boolToString cfg.reloadOnPluginChanges}

            shouldRestart=false
            if [[ "$restartPlugins" == true ]] && (( ''${#changedPlugins[@]} )); then
              shouldRestart=true
            fi
            if [[ "$restartSettings" == true && "$settingsChanged" == true ]]; then
              shouldRestart=true
            fi

            isRunning() {
              ${
                if pkgs.stdenv.hostPlatform.isLinux then
                  ''
                    ${lib.getExe' pkgs.glib "gdbus"} call --session \
                      --dest org.freedesktop.DBus \
                      --object-path /org/freedesktop/DBus \
                      --method org.freedesktop.DBus.NameHasOwner \
                      me.amankhanna.opendeck.SingleInstance 2>/dev/null | grep -Fq '(true,)'
                  ''
                else
                  ''
                    # The commands themselves do not start an inactive instance.
                    return 0
                  ''
              }
            }

            if [[ "$shouldRestart" == true ]]; then
              if isRunning; then
                ${cfg.package}/bin/opendeck --restart-if-running >/dev/null 2>&1 \
                  || verboseEcho "Could not restart OpenDeck; changes will apply on next launch"
              fi
            elif [[ "$reloadPlugins" == true ]] && (( ''${#changedPlugins[@]} )); then
              if isRunning; then
                for pluginId in "''${changedPlugins[@]}"; do
                  ${cfg.package}/bin/opendeck --reload-plugin "$pluginId" >/dev/null 2>&1 \
                    || verboseEcho "Could not reload OpenDeck plugin $pluginId; restart OpenDeck to apply the change"
                done
              fi
            fi
          ''}
        )
      fi
    '';
  };
}
