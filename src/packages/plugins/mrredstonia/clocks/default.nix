{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-mrredstonia-clocks";
  version = "0.9.5";

  # Tagged source already contains the static HTML/JS plugin; do not
  # use the packaged .streamDeckPlugin archive included in the repo.
  src = fetchFromGitHub {
    owner = "MrRedstonia";
    repo = "opendeck-clocks";
    tag = finalAttrs.version;
    hash = "sha256-8YEdahrIlquKQUU3DQH6947aQCY+d9oTlk1Or2aCeC0=";
  };

  pluginId = "com.mrredstonia.clocks.sdPlugin";
  pluginDir = finalAttrs.pluginId;
  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Configurable analogue and digital clocks for OpenDeck";
    homepage = "https://github.com/MrRedstonia/opendeck-clocks";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
