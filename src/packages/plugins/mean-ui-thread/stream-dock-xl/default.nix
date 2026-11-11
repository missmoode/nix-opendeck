{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-mean-ui-thread-stream-dock-xl";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "mean-ui-thread";
    repo = "opendeck-stream-dock-xl";
    tag = finalAttrs.version; # Upstream release tags have no v prefix.
    # Bootstrap with nix-update --version=skip before building.
    hash = "sha256-UdbNBqeMw8mhDqP7wXRvif8VmbzJGizAYBvuHdZKgQ4=";
  };

  cargoHash = "sha256-jfnNEf8YU9GveGI0jdOm32Xry+srQ/bbRL1RNHcg+fs=";

  pluginId = "com.github.mean-ui-thread.opendeck-stream-dock-xl.sdPlugin";
  binaryName = "opendeck-stream-dock-xl";
  binaryInstallPath = "opendeck-stream-dock-xl-linux";

  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets"
    cp -a assets/. "$plugin/assets/"
  '';

  udevRules = {
    "40-opendeck-stream-dock-xl.rules" = "${finalAttrs.src}/40-opendeck-stream-dock-xl.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "VSD Inside and Mirabox Stream Dock XL-family device support for OpenDeck";
    homepage = "https://github.com/mean-ui-thread/opendeck-stream-dock-xl";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
