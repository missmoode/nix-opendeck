{
  lib,
  fetchFromGitHub,
  pkg-config,

  libei,
  libxkbcommon,
  wayland,

  mkRustOpenDeckPlugin,
}:
mkRustOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-starterpack";
  version = "2.14.0";

  src = fetchFromGitHub {
    owner = "nekename";
    repo = "OpenDeck";
    tag = "v${finalAttrs.version}";
    rootDir = "plugins/com.amansprojects.starterpack.sdPlugin";
    hash = "sha256-JEZqvwiCX28jeXXJNRmg+h8LaIV4/BDdxA477a4J7oE=";
  };

  pluginId = "com.amansprojects.starterpack.sdPlugin";
  binaryName = "opendeck-starterpack";

  cargoHash = "sha256-s8GPWbPMJY9XTTC4QajY2sYUXcJ0g2OSl/YYhK/UZLQ=";

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
