{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-ibanks42-m18";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "ibanks42";
    repo = "opendeck-m18";
    tag = "v${finalAttrs.version}";
    # Bootstrap with nix-update --version=skip before building.
    hash = "sha256-bSoeM07K+mjvORm6ttNFG/R1APOT5ibHZIMOU3wYXoQ=";
  };

  cargoHash = "sha256-gXBkdzoyPCJpeQg6+7AvXTuDd3NoW/NX7bUw0rv3x9g=";

  pluginId = "com.github.ibanks42.opendeck-m18.sdPlugin";
  binaryName = "opendeck-m18";

  # Upstream's CodePaths maps each Linux target to a fixed filename.
  binaryInstallPath =
    if stdenv.hostPlatform.isAarch64 then "opendeck-m18-linux-aarch64" else "opendeck-m18-linux";

  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets" "$plugin/property_inspector"
    cp -a assets/. "$plugin/assets/"
    cp -a property_inspector/. "$plugin/property_inspector/"
  '';

  udevRules = {
    "40-opendeck-m18.rules" = "${finalAttrs.src}/40-opendeck-m18.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "VSD Inside M18 and Mirabox M18-family device support for OpenDeck";
    homepage = "https://github.com/ibanks42/opendeck-m18";
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
