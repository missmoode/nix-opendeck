# Note: nekename hasn't included a reproducible build script, unless we count the github actions?
# It's in prerelease, so I'm hesitant to create a derivation which builds it.
# They've also forgotten to include their license in the release, so we need to grab it from the git repo.
# This breaks the hash updating part of nix-update.
{
  lib,
  fetchzip,
  fetchFromGitHub,

  mkPrebuiltOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-discord";
  version = "0.5.0";

  src = fetchzip {
    url = "https://github.com/OpenActionPlugins/discord/releases/download/v${finalAttrs.version}/me.amankhanna.oadiscord.zip";
    hash = "sha256-65sI+CyXB0zQvwQ/SeY2Ij493hQDbWLEZfgR2D59D6o=";
  };

  licenseFiles = [
    "LICENSE.md"
  ];

  licenseSource = fetchFromGitHub {
    owner = "OpenActionPlugins";
    repo = "discord";
    tag = "v${finalAttrs.version}";
    hash = "sha256-h5/ld2BEVZa/4i5KLjutlUpcqPZOBq5+M4rlP4qap+w=";
  };

  pluginId = "me.amankhanna.oadiscord.sdPlugin";
  pluginDir = ".";

  meta = {
    description = "OpenAction plugin for controlling the Discord desktop client";
    homepage = "https://github.com/OpenActionPlugins/discord";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "nekename"
    ];
  };

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "OpenActionPlugins";
      repo = "discord";
    };
  };
})
