{
  nix-update-script,
}:
{
  pluginId,
  installPlugin,

  meta ? { },
  passthru ? { },

  runtimePackages ? [ ],
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
    inherit pluginId runtimePackages;

    updateScript = passthru.updateScript or (nix-update-script { });
  };
}
