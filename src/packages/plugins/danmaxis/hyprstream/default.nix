{
  lib,
  fetchFromGitHub,
  mkNpmOpenDeckPlugin,
  python3,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-danmaxis-hyprstream";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "danmaxis";
    repo = "hyprstream";
    rev = "74f9b5f18c494581045677f711b92bd672fcc7bc";
    hash = "sha256-Y3YjydO8AvNUzfnWuoG4Q6Tv2pGFcrNoLubwztE0iXY=";
  };

  pluginId = "com.danmaxis.hyprstream.sdPlugin";
  pluginDir = "packages/hyprstream/${finalAttrs.pluginId}";

  npmWorkspace = "packages/hyprstream";
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-DgLZBhME/LKwJO1gmNH/Sh+x7EFzHNoDhACdjfeteFo=";

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Hyprland workspace, window, and compositor controls for OpenDeck";
    homepage = "https://github.com/danmaxis/hyprstream";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [ "danmaxis" ];
  };

  passthru.updateScript = [
    "${python3}/bin/python3"
    "${../update.py}"
    "hyprstream"
  ];

})
