{
  lib,
  fetchFromGitHub,
  pkg-config,
  alsa-lib,
  wayland,

  mkRustOpenDeckPlugin,
  nix-update-script,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-biviale-pwsounddeck";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "biviale";
    repo = "pwsounddeck";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ofA2te/jpgSJ+k/z/ZvdyvEN8Mo4ME0IytVw03a0Oeo=";
  };

  cargoHash = "sha256-0KwsdBNyt9evXNA+hxpBQk1lQl/3cseENlvOYpKvvrA=";

  pluginId = "com.biviale.pwsounddeck.sdPlugin";
  binaryName = "pwsounddeck";
  binaryInstallPath = "pwsounddeck";

  assetsDir = finalAttrs.pluginId;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    alsa-lib
    wayland
  ];

  requiredCommands = [ "pactl" ];

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Soundboard with per-key playback and PipeWire/PulseAudio sink selection for OpenDeck";
    homepage = "https://github.com/biviale/pwsounddeck";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [ "biviale" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

})
