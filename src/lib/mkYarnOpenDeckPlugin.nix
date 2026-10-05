{
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  nodejs,

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
      serviceRequirements = attrs.serviceRequirements or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles or [ ];
      licenseSource = attrs.licenseSource or null;
    };
  in
  attrs
  // {
    yarnOfflineCache = fetchYarnDeps {
      yarnLock = finalAttrs.src + "/yarn.lock";
      hash = finalAttrs.yarnDepsHash;
    };

    yarnBuildScript = attrs.yarnBuildScript or "build";
    yarnBuildFlags = attrs.yarnBuildFlags or [ ];

    nativeBuildInputs = [
      yarnConfigHook
      yarnBuildHook
      nodejs
    ]
    ++ (attrs.nativeBuildInputs or [ ]);
  }
  // pluginAttrs
)
