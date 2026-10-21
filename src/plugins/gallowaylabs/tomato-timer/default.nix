{
  lib,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-gallowaylabs-tomato-timer";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "gallowaylabs";
    repo = "streamdeck-tomato-timer";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KIAYR6/Yk0GBHbZ+Tp5W16n/TmQomuahwRZFA/Zjafs=";
  };

  pluginId = "com.gallowaylabs.tomato.streamDeckPlugin";
  pluginDir = "Sources";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "A configurable timer for balancing work and break times on OpenDeck";
    homepage = "https://github.com/gallowaylabs/streamdeck-tomato-timer";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];

    authors = [
      "Matthew Galloway"
    ];
  };
})
