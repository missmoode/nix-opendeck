{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-havner-uinput-simulation";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "Havner";
    repo = "uinput-simulation";
    tag = "v${finalAttrs.version}";
    hash = "sha256-1UifkNA4R7lxP9vDjBWVM9U7CUNM3dyA2Mq4cxQcfz0=";
  };

  cargoHash = "sha256-2ZMKNKXoX6bKFwtquPQ/x3vnTfIWQZVO0PWbxCJxe7Q=";

  pluginId = "com.havner.uinput.sdPlugin";
  binaryName = "uinput-simulation";

  binaryInstallPath = "${stdenv.hostPlatform.rust.rustcTarget}/bin/uinput-simulation";

  udevRules = {
    "42-uinput-uaccess.rules" = "${finalAttrs.src}/udev/42-uinput-uaccess.rules";
  };

  licenseFiles = [ "LICENSE.md" ];

  meta = {
    description = "Linux keyboard and mouse simulation using uinput for OpenDeck";
    homepage = "https://github.com/Havner/uinput-simulation";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
