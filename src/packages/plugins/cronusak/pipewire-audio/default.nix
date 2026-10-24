{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-cronusak-pipewire-audio";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "CronusAK";
    repo = "Pulse-Audio-Stream-Deck-Plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-pDa6sZDHm+0Z4/7o00UCw+ue33Rk1wU7ExYz+Xwvhbk=";
  };

  pluginId = "com.sfgrimes.pipewire-audio.sdPlugin";
  pluginDir = ".";

  npmDepsHash = "sha256-JDZV1xUi2NPhiSTDfP/jr52peOerK4y2CoptRX12sCI=";

  dontNpmBuild = true;

  requiredCommands = [
    "wpctl"
    "pw-dump"
    "pactl"
  ];

  licenseFiles = [ "LICENSE" ];

  postInstall = ''
    rm -f "$out/${finalAttrs.pluginId}/build.sh"
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "PipeWire audio control plugin for OpenDeck";
    homepage = "https://github.com/CronusAK/Pulse-Audio-Stream-Deck-Plugin";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    authors = [ "sfgrimes" ];
  };
})
