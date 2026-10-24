{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-openactionplugins-counter";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "OpenActionPlugins";
    repo = "counter";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bLGgExjRlu//vs9ug7+KS45hTrwaytchIfM1OQJ/XW4=";
  };

  # Cargo.lock was added upstream after this release.
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  pluginId = "me.amankhanna.oacounter.sdPlugin";
  binaryName = "oacounter";
  binaryInstallPath = "oacounter-${stdenv.hostPlatform.rust.rustcTarget}";

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Persistent and temporary counters for OpenDeck";
    homepage = "https://github.com/OpenActionPlugins/counter";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
    authors = [ "nekename" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--src-only"
    ];
  };
})
