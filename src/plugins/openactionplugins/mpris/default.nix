{
  lib,
  fetchFromGitHub,
  stdenv,
  pkg-config,
  openssl,

  mkRustOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-openactionplugins-mpris";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "OpenActionPlugins";
    repo = "mpris";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7OcxkNlrnvDRCklYQKdAV84ieSH5nytGlTm5G2r6V1o=";
  };

  # Upstream does not commit Cargo.lock.
  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
  ];

  pluginId = "me.amankhanna.oampris.sdPlugin";
  binaryName = "oampris";

  # This is the filename expected by assets/manifest.json.
  binaryInstallPath = "oampris-${stdenv.hostPlatform.rust.rustcTarget}";

  serviceRequirements = [ "mpris-compatible player" ];

  licenseFiles = [
    "LICENSE"
  ];

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
