{
  lib,
  fetchFromGitHub,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-homeassistant";
  version = "3.8.4";

  src = fetchFromGitHub {
    owner = "cgiesche";
    repo = "streamdeck-homeassistant";
    tag = finalAttrs.version;
    hash = "sha256-/88lcyMEjLpMYTiScr2gj6LxdGwisBva47PXqEeSG/s=";
  };

  pluginId = "de.perdoctus.streamdeck.homeassistant.sdPlugin";
  pluginDir = "build/de.perdoctus.streamdeck.homeassistant.sdPlugin";

  npmDepsHash = "sha256-BCvXNM9OVIsJmE/Vd/7ZE9uel1dcXrIRrpUKizIxhLI=";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "Home Assistant plugin for Elgato Stream Deck";
    homepage = "https://github.com/cgiesche/streamdeck-homeassistant";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "Christoph Giesche"
    ];
  };
})
