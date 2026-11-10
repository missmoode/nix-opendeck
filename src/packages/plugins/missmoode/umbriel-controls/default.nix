{
  lib,
  fetchFromGitHub,
  stdenv,
  makeWrapper,
  nix-update-script,

  mkRustOpenDeckPlugin,

  defaultPalette ? null,
}:

mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-missmoode-umbriel-controls";
  version = "0.1.5";

  src = fetchFromGitHub {
    owner = "missmoode";
    repo = "opendeck-umbriel-controls";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+hRUHEAUIgdBe8Y5Zd6F/EsZ763ak8zdKeFSe1zQT6s=";
  };

  cargoHash = "sha256-Y8VmIR+DJ320kckXSdOrpCc64o48LFEhDANweCScGMs=";

  pluginId = "dev.moode.umbriel-controls.sdPlugin";
  binaryName = "umbriel-controls";
  binaryInstallPath = "umbriel-controls-${stdenv.hostPlatform.rust.rustcTarget}";

  licenseFiles = [
    "LICENSE"
    "crates/umbriel-ipc/LICENSE"
  ];

  # Match the upstream flake's optional fallback-palette override.
  nativeBuildInputs = lib.optionals (defaultPalette != null) [ makeWrapper ];

  postInstall = lib.optionalString (defaultPalette != null) ''
    wrapProgram "$out/${finalAttrs.pluginId}/${finalAttrs.binaryInstallPath}" \
      --set UMBRIEL_CONTROLS_DEFAULT_PALETTE ${lib.escapeShellArg defaultPalette}
  '';

  meta = {
    description = "Stream Deck controls for the Umbriel compositor";
    homepage = "https://github.com/missmoode/opendeck-umbriel-controls";
    license = lib.licenses.gpl3Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
