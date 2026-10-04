{
  lib,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-analogclock";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "elgatosf";
    repo = "streamdeck-analogclock";
    rev = "master";
    hash = "sha256-WGe/q5OGRhSL9OO9orWw1Ozj1enYDQMBGxl9wxgccrg=";
  };

  pluginId = "com.elgato.analogclock.sdPlugin";
  pluginDir = "Sources/${finalAttrs.pluginId}";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "Analog clock plugin for OpenDeck";
    homepage = "https://github.com/elgatosf/streamdeck-analogclock";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "Elgato"
    ];
  };
})
