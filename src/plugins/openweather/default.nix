{
  lib,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-openweather";
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "Lyzev";
    repo = "OpenWeather";
    tag = "v${finalAttrs.version}";
    hash = "sha256-X1GzMt5bBPsWa8Tf5F3bSiFqvXGrWB6WT+1CciaalEo=";
  };

  pluginId = "dev.lyzev.weather.sdPlugin";
  pluginDir = "src/${finalAttrs.pluginId}";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "A configurable timer for balancing work and break times on OpenDeck";
    homepage = "https://github.com/Lyzev/OpenWeather";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;

    authors = [
      "Lyzev"
    ];
  };
})
