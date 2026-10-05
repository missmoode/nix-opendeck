{
  lib,
  fetchFromGitHub,
  nodejs,
  python3,
  zip,

  mkNpmOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-redline-monitor";
  version = "1.0.9.1";

  src = fetchFromGitHub {
    owner = "kahikara";
    repo = "opendeck-redline-monitor";
    tag = "v.${finalAttrs.version}";
    hash = "sha256-h519U7QVrvpUiEAc9+Y+UiMT+JQag/sJ/b9eW1abiKk=";
  };

  pluginId = "com.kahikara.opendeck-redline.sdplugin";
  pluginDir = "dist/${finalAttrs.pluginId}";

  npmDepsHash = "sha256-G74N+sZW/wXUwuIajr9AGGXkS/Vc/v+oupYaxUNPpss=";

  nativeBuildInputs = [
    python3
    zip
  ];

  # keep the node version used to build and use it to run the plugin
  # without polluting the rest of the environment
  postPatch = ''
    patchShebangs build-plugin.sh start.sh

    substituteInPlace start.sh \
      --replace-fail \
      'NODE_BIN="''${NODE_BIN:-}"' \
      'NODE_BIN="''${NODE_BIN:-${nodejs}/bin/node}"'
  '';

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "kahikara";
      repo = "opendeck-redline-monitor";
      tagPrefix = "v.";
    };
  };

  serviceRequirements = [ "See upstream" ];

  licenseFiles = [
    "LICENSE"
  ];

  meta = {
    description = "OpenDeck plugin for Linux system monitoring";
    homepage = "https://github.com/kahikara/opendeck-redline-monitor";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [
      "kahikara"
    ];
  };
})
