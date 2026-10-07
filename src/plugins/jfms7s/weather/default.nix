{
  lib,
  fetchFromGitHub,
  stdenv,

  mkRustOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-jfms7s-weather";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "jfms7s";
    repo = "opendeck-weather";
    tag = "v${finalAttrs.version}";
    hash = "sha256-UmYOiV4aXGTZX0BRWY/Giaxopmu9wYM33Bp96MHu37U=";
  };

  pluginId = "com.jfms7s.weather.sdPlugin";
  binaryName = "opendeck-weather";

  # manifest.json expects the architecture-qualified binary directly
  # in the plugin root.
  binaryInstallPath = "opendeck-weather-${stdenv.hostPlatform.rust.rustcTarget}";

  cargoHash = "sha256-n5x7/1xrKP+fo4+QVjyufNti8LB6vKUJTht25FV3hwY=";

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "Current weather, daily forecast and air quality for OpenDeck";
    homepage = "https://github.com/jfms7s/opendeck-weather";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [ "jfms7s" ];
  };

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "jfms7s";
      repo = "opendeck-weather";
    };
  };
})
