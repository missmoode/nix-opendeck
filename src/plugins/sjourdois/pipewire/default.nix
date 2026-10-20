{
  lib,
  fetchFromGitHub,
  pkg-config,
  pipewire,
  clangStdenv,
  rustPlatform,

  mkRustOpenDeckPlugin,
}:
mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-sjourdois-pipewire";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "sjourdois";
    repo = "opendeck-pipewire";
    tag = "v${finalAttrs.version}";
    hash = "sha256-R2qg2+3Yp9Vb1Y+sA6vBZmalQni3XFfnP4mcbuKERlc=";
  };

  pluginId = "fr.jourdois.pipewire.sdPlugin";
  binaryName = "opendeck-pipewire";
  binaryInstallPath = "${clangStdenv.hostPlatform.rust.rustcTarget}/bin/${finalAttrs.binaryName}";

  cargoHash = "sha256-v/D1VZEd2YCjymXj8y2pZWPBoc9qJZs3Iss3HXcbkgo=";

  stdenv = clangStdenv;

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    pipewire
  ];

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "PipeWire / WirePlumber audio control plugin for OpenDeck";
    homepage = "https://github.com/sjourdois/opendeck-pipewire";
    license = lib.licenses.gpl3Plus;
    authors = [
      "sjourdois"
    ];
  };
})
