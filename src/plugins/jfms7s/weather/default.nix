{
  lib,
  fetchFromGitHub,
  stdenv,
  cacert,

  mkRustOpenDeckPlugin,
  nix-update-script,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-jfms7s-weather";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "jfms7s";
    repo = "opendeck-weather";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wyRSwTwnv825OPVWg1fetP8FKd1lbNm1fewclzQHYHY=";
  };

  pluginId = "com.jfms7s.weather.sdPlugin";
  binaryName = "opendeck-weather";

  # manifest.json expects the architecture-qualified binary directly
  # in the plugin root.
  binaryInstallPath = "opendeck-weather-${stdenv.hostPlatform.rust.rustcTarget}";

  cargoHash = "sha256-xAfRKlhH1bMMKWTvLt997IMVyJOJWo74zZX7oNW0Ylk=";

  licenseFiles = [
    "LICENSE"
  ];

  preCheck = ''
    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
  '';

  meta = {
    description = "Current weather, daily forecast and air quality for OpenDeck";
    homepage = "https://github.com/jfms7s/opendeck-weather";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [ "jfms7s" ];
  };

  passthru = {
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--use-github-releases"
      ];
    };
  };
})
