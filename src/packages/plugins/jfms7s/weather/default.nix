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
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "jfms7s";
    repo = "opendeck-weather";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Zjjp9exTAlsjeg7mPJWGk3zUZ+GG4M5nQQYSdoSUIQs=";
  };

  pluginId = "com.jfms7s.weather.sdPlugin";
  binaryName = "opendeck-weather";

  # manifest.json expects the architecture-qualified binary directly
  # in the plugin root.
  binaryInstallPath = "opendeck-weather-${stdenv.hostPlatform.rust.rustcTarget}";

  cargoHash = "sha256-dNabCncCjO2aJFO5nn0PGRa2sFEHpD177QZQCCRldBo=";

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
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
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
