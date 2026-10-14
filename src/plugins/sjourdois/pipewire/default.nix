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
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "sjourdois";
    repo = "opendeck-pipewire";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zj617q+6dbBVy8YJS7Psm1VCuEAbSK6xKj78VfUH1uc=";
  };

  pluginId = "fr.jourdois.pipewire.sdPlugin";
  binaryName = "opendeck-pipewire";

  cargoHash = "sha256-72Zd6Y5mtXAsJZ/O7ojBNZO8I+280B7LTmjd2Px+iKU=";

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
