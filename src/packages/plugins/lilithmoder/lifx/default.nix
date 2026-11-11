{
  lib,
  fetchFromGitHub,
  nix-update-script,
  stdenv,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-lilithmoder-lifx";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "lilithmoder";
    repo = "lifx-opendeck-plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-JohHgDjdP/IcrR/JHgXFxxzazOitYGZIBG6b+L+fT4E=";
  };

  cargoHash = "sha256-oVB+0DgzLNZlMcJrRUOSbwCQhBBxfdJWMpCx8PZC00c=";

  pluginId = "com.lilithmoder.lifx.sdPlugin";
  binaryName = "lifx-opendeck-plugin";
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then
      "bin/lifx-opendeck-plugin-macos-arm64"
    else
      "bin/lifx-opendeck-plugin";
  assetsDir = null;

  # The integration tests start a mock OpenDeck WebSocket server on
  # localhost, which the Darwin build sandbox blocks by default.
  __darwinAllowLocalNetworking = true;

  # Integration tests spawn the plugin, which writes logs to a
  # platform-specific user data directory. Provide a writable home
  # on Darwin and XDG data directory on Linux.
  preCheck = ''
    export HOME="$TMPDIR"
    export XDG_DATA_HOME="$TMPDIR/xdg-data"
  '';

  postInstall = ''
    cp -a "crates/plugin/${finalAttrs.pluginId}/." "$plugin/"
  '';

  licenseFiles = [
    "LICENSE-APACHE"
    "LICENSE-MIT"
  ];

  meta = {
    description = "Control LIFX smart lighting directly over the LAN from OpenDeck";
    homepage = "https://github.com/lilithmoder/lifx-opendeck-plugin";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
