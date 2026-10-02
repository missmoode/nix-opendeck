{
  stdenv,
  mkOpenDeckPlugin,
}:

package:

stdenv.mkDerivation (
  finalAttrs:
  let
    attrs = package finalAttrs;

    pluginAttrs = mkOpenDeckPlugin {
      pluginId = attrs.pluginId;

      installPlugin = ''
        cp -a "${finalAttrs.pluginDir}/." "$plugin/"
      '';

      runtimePackages = attrs.runtimePackages or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles or [ ];
      licenseSource = attrs.licenseSource or null;
    };
  in
  attrs
  // {
    dontConfigure = true;
    dontBuild = true;
  }
  // pluginAttrs
)
