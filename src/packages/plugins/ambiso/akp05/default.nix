{
  lib,
  fetchFromGitHub,
  writeText,
  stdenv,

  mkRustOpenDeckPlugin,
  nix-update-script,
}:

let
  mirajazz = fetchFromGitHub {
    owner = "ambiso";
    repo = "mirajazz";
    rev = "8b2bf1e8fc9a3005b9bff5f5f66bbdab86e62eab";
    hash = "sha256-LOyCDF7jxPewMhxgJIUc7wd4lIJcjXC1+WOBkKXBpJk=";
  };
in
mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-ambiso-akp05";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "ambiso";
    repo = "opendeck-akp05";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ll6FzO0fBD4+nhFIE72EWFLHENduwoO6o9KMEd+Ejh0=";
  };

  cargoHash = "sha256-KL8tlIyEjZN/JA3mAf0TEoX68LL73JE4UCAeLed7pGs=";

  pluginId = "com.github.ambiso.opendeck-akp05.sdPlugin";
  binaryName = "opendeck-akp05";

  # Match the platform-specific filenames in upstream's manifest.
  binaryInstallPath =
    if stdenv.hostPlatform.isDarwin then "opendeck-akp05-mac" else "opendeck-akp05-linux";

  assetsDir = null;

  # Upstream's Cargo.lock treats mirajazz as a local dependency,
  # but Cargo.toml points to a Git repository. Use a pinned Nix source.
  cargoPatches = [
    (writeText "use-pinned-mirajazz.patch" ''
      --- a/Cargo.toml
      +++ b/Cargo.toml
      @@ -25 +25 @@
      -mirajazz = { git = "https://github.com/ambiso/mirajazz.git" }
      +mirajazz = { path = "${mirajazz}" }
    '')
  ];

  postInstall = ''
    install -Dm644 manifest.json "$plugin/manifest.json"

    mkdir -p "$plugin/assets"
    cp -a assets/. "$plugin/assets/"
  '';

  udevRules = {
    "40-opendeck-akp05.rules" = "${finalAttrs.src}/40-opendeck-akp05.rules";
  };

  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Ajazz AKP05 and Mirabox N4-family device support for OpenDeck";
    homepage = "https://github.com/ambiso/opendeck-akp05";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
    authors = [ "ambiso" ];
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
