{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-havner-uinput-simulation";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "Havner";
    repo = "uinput-simulation";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XEA1btu8+qL4OjYN+Jthdy4kNJeb3L8tCUQ/SDtJjlI=";
  };

  cargoHash = "sha256-u7b72OCmwFoj9hVLoF6jFS9ZqoieCqposSyEbQIBJ+w=";

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
    authors = [ "Lukasz Pawelczyk" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
