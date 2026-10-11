{
  lib,
  fetchFromGitHub,
  stdenv,
  pkg-config,
  libpulseaudio,
  glib,
  gsettings-desktop-schemas,
  makeWrapper,

  mkRustOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-mdvictor-volume-controller";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "mdvictor";
    repo = "opendeck-volume-controller";
    tag = "v${finalAttrs.version}";
    hash = "sha256-AYi2r5SiZIX9Q6+JDGwgzp4ffC1ISYYIDS8siApqPUI=";
  };

  pluginId = "com.victormarin.volume-controller.sdPlugin";
  binaryName = "oa-volume-controller";

  binaryInstallPath = "oa-volume-controller-${stdenv.hostPlatform.rust.rustcTarget}";

  cargoHash = "sha256-d8qD78+n2E4GpsKa7M6QDfS/0xcwbZp++8ZcbegoIC0=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    libpulseaudio
  ];

  # Assets are stored at the repository root.
  assetsDir = null;

  postInstall = ''
    install -m644 manifest.json pi.html \
      "$out/${finalAttrs.pluginId}/"

    cp -r img "$out/${finalAttrs.pluginId}/"

    wrapProgram "$out/${finalAttrs.pluginId}/${finalAttrs.binaryInstallPath}" \
      --prefix PATH : "${lib.makeBinPath [ glib ]}" \
      --prefix XDG_DATA_DIRS : "${glib.getSchemaPath gsettings-desktop-schemas}"
  '';

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Per-application audio volume controller for OpenDeck";
    homepage = "https://github.com/mdvictor/opendeck-volume-controller";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    authors = [ "mdvictor" ];
  };

  passthru = {
    updateScript = mkGitHubReleaseUpdateScript {
      owner = "mdvictor";
      repo = "opendeck-volume-controller";
    };
  };
})
