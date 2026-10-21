{
  lib,
  fetchFromGitHub,
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

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    libei
    libxkbcommon
    wayland
  ];

  meta = {
    description = "OpenDeck Starter Pack plugin";
    homepage = "https://github.com/nekename/OpenDeck";
    license = lib.licenses.gpl3Plus;

    authors = [
      "nekename"
    ];
  };
})
