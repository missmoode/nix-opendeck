{
  stdenv,
  fetchPnpmDeps,
  pnpm_10,
  pnpmConfigHook,
  pnpmBuildHook,
  nodejs,

  mkOpenDeckPlugin,
}:

package:

stdenv.mkDerivation (
  finalAttrs:
  let
    attrs = package finalAttrs;
    pnpm = attrs.pnpm or pnpm_10;

    pluginAttrs = mkOpenDeckPlugin {
      pluginId = attrs.pluginId;

      installPlugin = ''
        cp -a "${finalAttrs.pluginDir}/." "$plugin/"
      '';

      requiredCommands = attrs.requiredCommands or [ ];

      meta = attrs.meta or { };
      passthru = attrs.passthru or { };
      licenseFiles = attrs.licenseFiles;
      udevRules = attrs.udevRules or { };
    };
  in
  (removeAttrs attrs [
    "udevRules"
    "pnpm"
  ])
  // {
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      inherit pnpm;
      fetcherVersion = 4;
      hash = finalAttrs.pnpmDepsHash;
      patches = attrs.patches or [ ];
    };

    nativeBuildInputs = [
      nodejs
      pnpm
      pnpmConfigHook
      pnpmBuildHook
    ]
    ++ (attrs.nativeBuildInputs or [ ]);
  }
  // pluginAttrs
)
