{
  lib,
  fetchFromGitHub,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-multi-obs-controller";
  version = "0.8.3";

  src = fetchFromGitHub {
    owner = "theca11";
    repo = "multi-obs-controller";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-j/Y12Yi3/U37+QLM5xwaaCWmqzjNloiQxSgP2GEfHpc=";
  };

  pluginId = "dev.theca11.multiobs.sdPlugin";
  pluginDir = "build/${finalAttrs.pluginId}";

  npmDepsHash = "sha256-VJwtguDjRBjzVPZnsnBySdg55+igmvtZXBT1xb0egAY=";

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
