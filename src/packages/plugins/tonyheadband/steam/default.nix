{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkPnpmOpenDeckPlugin,
}:

mkPnpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-tonyheadband-steam";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "TonyHeadband";
    repo = "opendeck-steam-plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Fiu8jFQ7wQULdFYB9nlud1qt1OPAYhJx+cdpFvz3AqI=";
  };

  pnpmDepsHash = "sha256-zWqRrys7OtvAqFpdYpUjmR6L3Bs+A6mLTchqq0cBonI=";

  pluginId = "io.github.tonyheadband.opendeck-steam.sdPlugin";
  pluginDir = finalAttrs.pluginId;

  requiredCommands = [ "xdg-open" ];
  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Control the Steam client, games, and friend presence from OpenDeck";
    homepage = "https://github.com/TonyHeadband/opendeck-steam-plugin";
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
