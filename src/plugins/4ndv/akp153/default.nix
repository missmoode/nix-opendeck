{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-4ndv-akp153";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "4ndv";
    repo = "opendeck-akp153";
    tag = "v${finalAttrs.version}";
    hash = "sha256-PyxKmjtu9cxBAXvVHadJwtDoDu66myihBZb0rTIaCfg=";
  };

  cargoHash = "sha256-k9tIxMqAiHKzF9FHWCANsIz5l4dVcBQDLHo3hlweD+E=";

  pluginId = "st.lynx.plugins.opendeck-akp153.sdPlugin";
  binaryName = "opendeck-akp153";

  # Upstream uses fixed platform filenames rather than target triples.
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then "opendeck-akp153-mac" else "opendeck-akp153-linux";

  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets"
    cp -a assets/. "$plugin/assets/"
  '';

  udevRules = {
    "40-opendeck-akp153.rules" = "${finalAttrs.src}/40-opendeck-akp153.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Ajazz AKP153 and Mirabox HSV293S-family device support for OpenDeck";
    homepage = "https://github.com/4ndv/opendeck-akp153";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
    authors = [ "Andrey Viktorov" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
