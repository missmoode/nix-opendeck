{
  lib,
  fetchFromGitHub,
  stdenv,

  mkRustOpenDeckPlugin,
  nix-update-script,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-ambiso-akp05";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "ambiso";
    repo = "opendeck-akp05";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Nsv+gWFu1yTW8bDylfA5Bv1FXSll6vyOqeHiRr8u4R0=";
  };

  cargoHash = "sha256-89FrmARZxpmM70f4nnV9Uxpor6m2eRTnNiq6AAipuSw=";

  pluginId = "com.github.ambiso.opendeck-akp05.sdPlugin";
  binaryName = "opendeck-akp05";

  # Match the platform-specific filenames in upstream's manifest.
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then "opendeck-akp05-mac" else "opendeck-akp05-linux";

  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets"
    cp -a assets/. "$plugin/assets/"
  '';

  udevRules = {
    "40-opendeck-akp05.rules" = "${finalAttrs.src}/40-opendeck-akp05.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Ajazz AKP05 and Mirabox N4-family device support for OpenDeck";
    homepage = "https://github.com/ambiso/opendeck-akp05";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
