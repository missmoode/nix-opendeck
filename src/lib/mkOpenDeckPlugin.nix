# For packaging: Where there are software dependencies, package them.
# Declare system service requirements where needed - things that the plugin expects to exist.
{
  lib,
  stdenv,
  runCommand,
  nix-update-script,
  jq,
}:
{
  pluginId,
  installPlugin,

  meta ? { },
  passthru ? { },

  # Commands the plugin directly invokes at runtime which must be
  # provided by the user's environment, rather than by Nix-Opendeck.
  requiredCommands ? [ ],

  licenseFiles ? [ ],

  # For plugins which provide compatibility with non-elgato USB hardware.
  # Optional udev rules: output filename -> source file.
  udevRules ? { },

  # Useful for retrieving license files when the upstream repo hasn't
  # placed them in an expected place, or has ommitted them from the
  # current source. You only need to set it if the licenses can't be
  # found from `src`.
  licenseSource ? null,
}:
{
  installPhase = ''
    runHook preInstall

    plugin="$out/${pluginId}"
    mkdir -p "$plugin"

    ${installPlugin}

    ${builtins.concatStringsSep "\n" (
      map (licenseFile: ''
        install -Dm644 \
          "${if licenseSource != null then licenseSource else "$src"}/${licenseFile}" \
          "$plugin/${licenseFile}"
      '') licenseFiles
    )}

    runHook postInstall

    # Validate the installed plugin after all post-install hooks have run.
    manifest="$plugin/manifest.json"

    if [[ ! -f "$manifest" ]]; then
      echo "error: OpenDeck plugin '${pluginId}' is missing manifest.json" >&2
      exit 1
    fi

    if ! ${jq}/bin/jq -e 'type == "object"' "$manifest" > /dev/null; then
      echo "error: OpenDeck plugin '${pluginId}' has an invalid manifest.json" >&2
      exit 1
    fi
  '';

  inherit meta;

  passthru =
    passthru
    // {
      inherit pluginId requiredCommands;

      updateScript =
        passthru.updateScript or (nix-update-script {
          extraArgs = [ "--flake" ];
        });
    }
    // lib.optionalAttrs (stdenv.hostPlatform.isLinux && udevRules != { }) {
      udev = runCommand "${pluginId}-udev-rules" { } ''
        mkdir -p "$out/lib/udev/rules.d"

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: source: ''
            install -Dm644 \
              ${lib.escapeShellArg (toString source)} \
              "$out/lib/udev/rules.d/"${lib.escapeShellArg name}
          '') udevRules
        )}
      '';
    };
}
