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
    rev = "ecbdf69ed335d57de21e77968a0b536b04bfa662"; # upstream doesn't properly tag, so we'll just use the commit with the message "Analog Clock V2"
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
