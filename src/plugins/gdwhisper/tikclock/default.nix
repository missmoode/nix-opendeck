{
  lib,
  fetchFromGitHub,
  stdenv,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-gdwhisper-tikclock";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "GDWhisper";
    repo = "opendeck-tikclock";
    tag = "v${finalAttrs.version}";
    hash = "sha256-eSXQX1Og3beQM3twyheRD+rXrbT4XlJzv9cqOPmTY68=";
  };

  pluginId = "com.gdwhisper.tikclock.sdPlugin";
  binaryName = "tikclock";

  # The upstream repository keeps the complete plugin bundle here:
  # manifest.json, propertyInspector/, icons/, etc.
  assetsDir = "com.gdwhisper.tikclock.sdPlugin";

  # The manifest expects the platform-specific binary at this exact path.
  binaryInstallPath = "bin/tikclock-${stdenv.hostPlatform.rust.rustcTarget}";

  cargoHash = "sha256-jiPBACRwUiVj1baSknU5TnnDFiH/E01O/SBhyALB5Vk=";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "Digital clock plugin for OpenDeck";
    homepage = "https://github.com/GDWhisper/opendeck-tikclock";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [
      "GDWhisper"
    ];
  };
})
