{
  buildNpmPackage,
  mkOpenDeckPlugin,
}:

package:

buildNpmPackage (
  finalAttrs:
  let
    attrs = package finalAttrs;

    pluginAttrs = mkOpenDeckPlugin {
      pluginId = attrs.pluginId;

      installPlugin = ''
        cp -a "${finalAttrs.pluginDir}/." "$plugin/"
      '';

      runtimeRequirements = attrs.runtimeRequirements or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles or [ ];
      licenseSource = attrs.licenseSource or null;
    };
  in
  attrs // pluginAttrs
)
