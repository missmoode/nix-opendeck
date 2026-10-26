{
  lib,
  fetchFromGitHub,
  fetchurl,
  pkg-config,
  stdenv,

  libei,
  libxkbcommon,
  wayland,

  mkRustOpenDeckPlugin,
}:
mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-nekename-starterpack";
  version = "2.14.2";

  src = fetchFromGitHub {
    owner = "nekename";
    repo = "OpenDeck";
    tag = "v${finalAttrs.version}";
    rootDir = "plugins/com.amansprojects.starterpack.sdPlugin";
    hash = "sha256-WRmkB/r8FFA5rWHDiGtYra5vtIJpgSSpcR6dqD+HV1o=";
  };

  pluginId = "com.amansprojects.starterpack.sdPlugin";
  binaryName = "opendeck-starterpack";
  binaryInstallPath = "${stdenv.hostPlatform.rust.rustcTarget}/bin/${finalAttrs.binaryName}";

  cargoHash = "sha256-maCwWfZzsko2t4BtwJJiIBqK4lZYuUZgz4MR7YvWAy4=";

  licenseFiles = [
    (fetchurl {
      name = "LICENSE.md";
      url = "https://raw.githubusercontent.com/nekename/OpenDeck/v${finalAttrs.version}/LICENSE.md";
      hash = "sha256-zFRw/u1mGSOH8GrpOu0L1P765aX9fB5UpKz06mTxAos=";
    })
  ];

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libei
    libxkbcommon
    wayland
  ];

  meta = {
    description = "OpenDeck Starter Pack plugin";
    homepage = "https://github.com/nekename/OpenDeck";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];

    authors = [
      "nekename"
    ];
  };
})
