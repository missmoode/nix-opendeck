# For packaging: Where there are software dependencies, package them.
# Declare system service requirements where needed - things that the plugin expects to exist.
{
  nix-update-script,
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
  '';

  inherit meta;

  passthru = passthru // {
    inherit pluginId requiredCommands;

    updateScript = passthru.updateScript or (nix-update-script { });
  };
}
