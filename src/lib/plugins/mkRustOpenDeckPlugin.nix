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
      udevRules = attrs.udevRules or { };
    };
  in
  (removeAttrs attrs [ "udevRules" ])
  // pluginAttrs
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    preBuild = ''
      ${attrs.preBuild or ""}

      # Avoid embedding Nix's variable Darwin build directory in Rust binaries.
      # Explicitly retain Nixpkgs' frame-pointer flag because RUSTFLAGS
      # overrides Cargo's target-specific rustflags.
      export RUSTFLAGS="''${RUSTFLAGS:+$RUSTFLAGS }-Cforce-frame-pointers=yes --remap-path-prefix=$NIX_BUILD_TOP=/build"

      export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:+$NIX_CFLAGS_COMPILE }-ffile-prefix-map=$NIX_BUILD_TOP=/build"
    '';
  }

)
