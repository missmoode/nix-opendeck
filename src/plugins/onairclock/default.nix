{
  lib,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-onairclock";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "wortkrieg";
    repo = "streamdeck-onairclock";
    tag = "1.3.0"; # Upstream forgot to add a V
    hash = "sha256-lFknS4VbkManf56YivdvV4xD5MKc9afpSsMkkcpacqQ=";
  };

  pluginId = "fail.marc.onairclock.sdPlugin";
  pluginDir = "${finalAttrs.pluginId}";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "A versatile and configurable broadcast-inspired on air clock for OpenDeck.";
    homepage = "https://marc.fail/onairclock/";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "wortkrieg"
    ];
  };
})
