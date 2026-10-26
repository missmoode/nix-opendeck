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

      requiredCommands = attrs.requiredCommands or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles or [ ];
      udevRules = attrs.udevRules or { };
    };
  in
  (removeAttrs attrs [ "udevRules" ])
  // {
    dontConfigure = true;
    dontBuild = true;
  }
  // pluginAttrs
)
