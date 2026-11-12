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
  version = "0.5.2";

  src = fetchFromGitHub {
    owner = "biviale";
    repo = "pwsounddeck";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wblti5GC9jmn9r2xMCCW7nS3R8+4J96cONzEvMaeMHI=";
  };

  cargoHash = "sha256-NN3FOSSsohXkvNzSzHZWGUyZYPKytCKCsRbWmSQF6nU=";

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
