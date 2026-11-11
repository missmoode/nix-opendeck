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
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "biviale";
    repo = "pwsounddeck";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Lx42Lg4FYfYxmDPyVS7BTB1SpEBwwUCWpXNxCK8AZI0=";
  };

  cargoHash = "sha256-IAMzFbjS8x1VB2bhn+RsKNs/LsW5+eThmRY6VQgOBqY=";

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
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

})
