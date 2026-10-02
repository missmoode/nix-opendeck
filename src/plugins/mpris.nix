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
  pname = "opendeck-mpris";
  version = "1.4.0";

  src = fetchzip {
    url = "https://github.com/OpenActionPlugins/mpris/releases/download/v${finalAttrs.version}/me.amankhanna.oampris.zip";
    hash = "sha256-CUWce9FWKXLMLZqknPPuoCja9okC08P44Czbr4dR3FM=";
  };

  licenseFiles = [
    "LICENSE"
  ];

  licenseSource = fetchFromGitHub {
    owner = "OpenActionPlugins";
    repo = "mpris";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7OcxkNlrnvDRCklYQKdAV84ieSH5nytGlTm5G2r6V1o=";
  };

  pluginId = "me.amankhanna.oampris.sdPlugin";
  pluginDir = ".";

  meta = {
    description = "OpenAction plugin for controlling media players on Linux using the MPRIS protocol";
    homepage = "https://github.com/OpenActionPlugins/mpris";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "nekename"
    ];
  };

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "OpenActionPlugins";
      repo = "mpris";
    };
  };
})
