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
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "sjourdois";
    repo = "opendeck-pipewire";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wDV55RkR6vgQOOnReXXTNwZmDegsPOyvdafNSt7fb5Q=";
  };

  pluginId = "fr.jourdois.pipewire.sdPlugin";
  binaryName = "opendeck-pipewire";
  binaryInstallPath = "${clangStdenv.hostPlatform.rust.rustcTarget}/bin/${finalAttrs.binaryName}";

  cargoHash = "sha256-FdaU6hLFQVTKTIz5xvZX1YLHabuyKrvg6ipOMteMxew=";

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
    platforms = lib.platforms.linux;
  };
})
