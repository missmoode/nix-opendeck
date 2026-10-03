{
  lib,
  fetchFromGitHub,
  mkGitHubReleaseUpdateScript,

  mkYarnOpenDeckPlugin,
}:

mkYarnOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-xivdeck";
  version = "0.4.5";

  src = fetchFromGitHub {
    owner = "KazWolfe";
    repo = "XIVDeck";
    tag = "v${finalAttrs.version}";
    rootDir = "SDPlugin";
    hash = "sha256-Cc9eRudN4BwGGwoPf+ODOplvuIZPSlAoWweHoe5kaZQ=";
  };

  pluginId = "dev.wolf.xivdeck.sdPlugin";
  pluginDir = "dist/dev.wolf.xivdeck.sdPlugin";

  yarnDepsHash = "sha256-ecluMlQxkiHzv4pxaPOIBLWP8xvHzOma/z9KLnxE+FA=";

  licenseFiles = [ ];

  meta = {
    description = "XIVDeck Stream Deck plugin";
    homepage = "https://github.com/KazWolfe/XIVDeck";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.linux;

    authors = [
      "KazWolfe"
    ];
  };
  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "KazWolfe";
      repo = "XIVDeck";
    };
  };
})
