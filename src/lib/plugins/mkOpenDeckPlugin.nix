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

  # Either a file name relative to the source root
  # or a fetcher for a singular file (with a name attribute)
  # see nekename/starterpack plugin
  licenseFiles ? [ ],

  # For plugins which provide compatibility with non-elgato USB hardware.
  # Optional udev rules: output filename -> source file.
  udevRules ? { },
}:
{
  installPhase = ''
    runHook preInstall

    plugin="$out/${pluginId}"
    mkdir -p "$plugin"

    ${installPlugin}

    ${lib.concatMapStringsSep "\n" (
      file:
      let
        fromSrc = builtins.isString file;
        filename = if fromSrc then file else file.name;

        source =
          if fromSrc then ''"$src"/${lib.escapeShellArg file}'' else lib.escapeShellArg (toString file);
      in
      ''
        install -Dm644 \
          ${source} \
          "$plugin"/${lib.escapeShellArg filename}
      ''
    ) licenseFiles}

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
