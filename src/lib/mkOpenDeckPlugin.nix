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

  # Purely informational metadata. Services or applications the plugin
  # interacts with at runtime, but which are not dependencies provided
  # by the plugin package.
  serviceRequirements ? [ ],

  licenseFiles ? [ ],
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
    inherit pluginId requiredCommands serviceRequirements;

    updateScript = passthru.updateScript or (nix-update-script { });
  };
}
