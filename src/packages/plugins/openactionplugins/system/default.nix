{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-openactionplugins-system";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "OpenActionPlugins";
    repo = "system";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QZYI8koKbdRylYMAkw27yx/zFWp1zAx3aqqZJYehHTE=";
  };

  # Release predates the upstream lockfile and dependency updates.
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  pluginId = "me.amankhanna.oasystem.sdPlugin";
  binaryName = "oasystem";
  binaryInstallPath = "oasystem-${stdenv.hostPlatform.rust.rustcTarget}";

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "CPU, memory, uptime and OS information for OpenDeck";
    homepage = "https://github.com/OpenActionPlugins/system";
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
