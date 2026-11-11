{
  lib,
  fetchFromGitHub,
  nix-update-script,
  stdenv,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-mdvictor-graphs";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "mdvictor";
    repo = "opendeck-graphs";
    tag = "v${finalAttrs.version}";
    hash = "sha256-268DNA4R8B0I+vY3xNdO37SDvKTGtHscVfgZ8hHhZL0=";
  };

  cargoHash = "sha256-It7GLsLRW/7M/hkKZp+f6riuwfZS8IM6Jip0Wh0P68U=";

  pluginId = "com.victormarin.graphs.sdPlugin";
  binaryName = "oa-graphs";
  binaryInstallPath = "oa-graphs-${stdenv.hostPlatform.rust.rustcTarget}";
  assetsDir = null;

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"
    install -Dm644 pi.html "$plugin/pi.html"
    mkdir -p "$plugin/img" "$plugin/fonts"
    cp -a img/. "$plugin/img/"
    cp -a fonts/. "$plugin/fonts/"
  '';

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Display live hardware sensor graphs on OpenDeck keys";
    homepage = "https://github.com/mdvictor/opendeck-graphs";
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
