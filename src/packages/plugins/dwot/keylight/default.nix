{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-dwot-keylight";
  version = "0.5.3";

  src = fetchFromGitHub {
    owner = "dwot";
    repo = "opendeck-keylight";
    tag = "v${finalAttrs.version}";
    hash = "sha256-FTtAYQZOiJ8x7nmkHU5cDcBbyJKzuuxtsfpX6jkOZ58=";
  };

  npmDepsHash = "sha256-1QzCRk14KfvyQwkdc+TxK9HjEt/STm0zI/e3AlM8xP0=";

  pluginId = "me.dwot.keylight.sdPlugin";
  pluginDir = ".";

  # Source contains the runnable JavaScript and the platform override
  # manifest.linux.json. We only need to install its npm dependencies.
  dontNpmBuild = true;

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Control Elgato Key Lights directly over the local network";
    homepage = "https://github.com/dwot/opendeck-keylight";
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
