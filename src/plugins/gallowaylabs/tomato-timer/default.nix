{
  lib,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-gallowaylabs-tomato-timer";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "gallowaylabs";
    repo = "streamdeck-tomato-timer";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zMSW/rNlR1nFkIF/YyL+k1hdAnJMP+baxJwcrdlmrYs=";
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
    platforms = lib.platforms.linux;

    authors = [
      "Matthew Galloway"
    ];
  };
})
