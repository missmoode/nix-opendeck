{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-4ndv-akp03";
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "4ndv";
    repo = "opendeck-akp03";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Q7ObIEviQGa+/g1dvZ/s33fsNU4oBQggtdYOoZi15Vg=";
  };

  cargoHash = "sha256-eTPczCkARQOfVqnsRF8AXPIde3uHYEeHwKU9MO/UqFo=";

  pluginId = "st.lynx.plugins.opendeck-akp03.sdPlugin";
  binaryName = "opendeck-akp03";

  # Upstream uses fixed platform filenames rather than target triples.
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then "opendeck-akp03-mac" else "opendeck-akp03-linux";

  # The manifest lives at the repository root, and its icon path
  # requires the assets/ directory to remain intact.
  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets"
    cp -a assets/. "$plugin/assets/"
  '';

  # Device permissions are packaged separately from the plugin binary.
  udevRules = {
    "40-opendeck-akp03.rules" = "${finalAttrs.src}/40-opendeck-akp03.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Ajazz AKP03 and Mirabox N3-family device support for OpenDeck";
    homepage = "https://github.com/4ndv/opendeck-akp03";
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
