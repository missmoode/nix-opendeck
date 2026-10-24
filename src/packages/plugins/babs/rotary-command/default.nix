{
  lib,
  fetchFromGitHub,
  stdenv,
  bash,
  makeWrapper,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-babs-rotary-command";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "babs";
    repo = "opendeck-plugins-rotary-command";
    tag = "v${finalAttrs.version}";
    hash = "sha256-0UuDiyLZv1TX/VT7LD65b4XiYwmM3xiu871PGfQVsB0=";
  };

  cargoHash = "sha256-TSdQJgdkkSfpPga+0s/kWamWR3MGZXSHR6qcwMY4438=";

  pluginId = "info.degois.damien.opendeck.plugins.rotary-command.sdPlugin";
  binaryName = "opendeck-rotary-generic";

  # This plugin's manifest deviates from the norm by
  # using a different binary path on Darwin.
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then
      "opendeck-rotary-generic-universal-apple-darwin"
    else
      "opendeck-rotary-generic-${stdenv.hostPlatform.rust.rustcTarget}";

  nativeBuildInputs = [ makeWrapper ];

  # Commands are executed via `sh -c`. Provide the shell without
  # replacing the user's PATH, which supplies their custom commands.
  postInstall = ''
    wrapProgram "$out/${finalAttrs.pluginId}/${finalAttrs.binaryInstallPath}" \
      --prefix PATH : "${lib.makeBinPath [ bash ]}"
  '';

  meta = {
    description = "Execute custom shell commands using Stream Deck rotary encoders";
    homepage = "https://github.com/babs/opendeck-plugins-rotary-command";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
    authors = [ "babs" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
