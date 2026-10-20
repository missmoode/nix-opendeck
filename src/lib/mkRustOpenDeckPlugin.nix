{
  lib,
  rustPlatform,
  stdenv,

  mkOpenDeckPlugin,
}:

package:

rustPlatform.buildRustPackage (
  finalAttrs:
  let
    attrs = package finalAttrs;

    binaryPath =
      attrs.binaryPath
        or "target/${stdenv.hostPlatform.rust.rustcTarget}/release/${finalAttrs.binaryName}";

    # The destination comes from the plugin's manifest, not Cargo conventions.
    binaryInstallPath = attrs.binaryInstallPath;

    assetsDir = attrs.assetsDir or "assets";

    pluginAttrs = mkOpenDeckPlugin {
      pluginId = finalAttrs.pluginId;

      installPlugin = ''
        ${lib.optionalString (assetsDir != null) ''
          if [ -d "${assetsDir}" ]; then
            cp -a "${assetsDir}/." "$plugin/"
          fi
        ''}

        install -Dm755 \
          "${binaryPath}" \
          "$plugin/${binaryInstallPath}"
      '';

      requiredCommands = attrs.requiredCommands or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles or [ ];
      licenseSource = attrs.licenseSource or null;
    };
  in
  attrs // pluginAttrs
)
