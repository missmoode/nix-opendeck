{
  lib,
  fetchFromGitHub,
  mkGitHubReleaseUpdateScript,
  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-multi-obs-controller";
  version = "0.8.2";

  src = fetchFromGitHub {
    owner = "theca11";
    repo = "multi-obs-controller";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-2k5EWYrhYmp4GD2LxupNpTRPpFTw6O47WpFfo4wVpG8=";
  };

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "theca11";
      repo = "multi-obs-controller";
    };
  };

  pluginId = "dev.theca11.multiobs.sdPlugin";
  pluginDir = "build/${finalAttrs.pluginId}";

  npmDepsHash = "sha256-VJwtguDjRBjzVPZnsnBySdg55+igmvtZXBT1xb0egAY=";

  serviceRequirements = [ "obs studio" ];

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "Control one or multiple OBS Studio instances from OpenDeck";
    homepage = "https://github.com/theca11/multi-obs-controller";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "the_ca11"
    ];
  };
})
