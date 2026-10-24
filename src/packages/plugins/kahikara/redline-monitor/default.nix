{
  lib,
  fetchFromGitHub,
  python3,
  zip,
  nix-update-script,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-kahikara-redline-monitor";
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
  '';

  passthru = {
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--use-github-releases"
        "--version-regex"
        "^v[.]?([0-9.]+)$"
      ];
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
