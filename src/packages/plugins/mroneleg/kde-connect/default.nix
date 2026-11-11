{
  lib,
  fetchFromGitHub,
  nix-update-script,
  stdenv,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-mroneleg-kde-connect";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "mroneleg";
    repo = "kde-connect-opendeck";
    tag = "v${finalAttrs.version}";
    hash = "sha256-f3z6+kQa8Yv4sYN/djKxZSHpQUmJc6FmIoEtRo2y9nk=";
  };

  cargoHash = "sha256-pf22YX0v6BbTKIz5h3Q/ZzllJpyMNl0FbMcDrRZPppc=";

  pluginId = "com.mroneleg.kdeconnect.sdPlugin";
  binaryName = "kdeconnect-opendeck";
  binaryInstallPath = "kdeconnect-opendeck-${stdenv.hostPlatform.rust.rustcTarget}";
  assetsDir = "assets";

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Control KDE Connect devices from OpenDeck using D-Bus";
    homepage = "https://github.com/mroneleg/kde-connect-opendeck";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
