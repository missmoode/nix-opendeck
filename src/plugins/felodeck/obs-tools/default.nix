{
  lib,
  fetchFromGitHub,
  stdenv,
  nix-update-script,

  mkRustOpenDeckPlugin,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-felodeck-obs-tools";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "FeloDeck";
    repo = "obs-tools";
    tag = "v${finalAttrs.version}";
    hash = "sha256-adMApJU6BOSVE9lF76+ZgVljYI+7b+LMewjdU/0ClH0=";
  };

  cargoHash = "sha256-7W5D64Zpiksoo5lvUR0Mmb8XChNX3ZdYo6IhgBzEFFo=";
  cargoBuildFlags = [
    "--package"
    "obs-tools"
  ];

  preBuild = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # ring's object-file paths vary between Nix builds.
    # Exclude their debug-map entries during linking so they cannot
    # affect the content-derived Mach-O UUID or code signature.
    export RUSTFLAGS="''${RUSTFLAGS:+$RUSTFLAGS }-C link-arg=-Wl,-S"
  '';

  pluginId = "de.felitendo.obs-tools.sdPlugin";
  assetsDir = finalAttrs.pluginId;
  binaryName = "obs-tools";
  binaryInstallPath = "bin/${stdenv.hostPlatform.rust.rustcTarget}/obs-tools";

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Advanced OBS Studio controls for OpenDeck";
    homepage = "https://github.com/FeloDeck/obs-tools";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
    authors = [ "Felitendo" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
