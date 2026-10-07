{
  lib,
  fetchFromGitHub,
  stdenv,
  deno,
  pkg-config,
  openssl,

  mkRustOpenDeckPlugin,
  mkGitHubReleaseUpdateScript,
}:

mkRustOpenDeckPlugin (
  finalAttrs:
  let
    denoDeps = stdenv.mkDerivation {
      pname = "${finalAttrs.pname}-deno-deps";
      version = finalAttrs.version;

      dontUnpack = true;

      nativeBuildInputs = [
        deno
      ];

      outputHash = "sha256-0QPWjZ9u/Ytiph9vy7FpyGJQwDC//VhzTYYka2t0NVg=";
      outputHashMode = "recursive";

      buildPhase = ''
        runHook preBuild

        mkdir -p "$TMPDIR/pi"
        cp -r "${finalAttrs.src}/pi/." "$TMPDIR/pi/"
        cp "${./deno.lock}" "$TMPDIR/pi/deno.lock"

        cd "$TMPDIR/pi"

        export DENO_DIR="$TMPDIR/deno"

        deno ci

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"
        cp -a "$TMPDIR/pi/node_modules" "$out/"

        runHook postInstall
      '';
    };
  in
  {
    pname = "opendeck-openactionplugins-discord";
    version = "0.5.0";

    src = fetchFromGitHub {
      owner = "OpenActionPlugins";
      repo = "discord";
      tag = "v${finalAttrs.version}";
      hash = "sha256-h5/ld2BEVZa/4i5KLjutlUpcqPZOBq5+M4rlP4qap+w=";
    };

    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "discord-ipc-rust-0.1.4" = "sha256-6zTIJwZSxUsrma9005sfyInBcM7sk9W08+TfolUhlZY=";
      };
    };

    postPatch = ''
      ln -s ${./Cargo.lock} Cargo.lock
      ln -s ${./deno.lock} pi/deno.lock
    '';

    nativeBuildInputs = [
      deno
      pkg-config
    ];

    buildInputs = [
      openssl
    ];

    preBuild = ''
      cp -a ${denoDeps}/node_modules pi/

      cd pi
      deno task --frozen-lockfile build
      cd ..
    '';

    pluginId = "me.amankhanna.oadiscord.sdPlugin";
    binaryName = "oadiscord";

    binaryInstallPath = "oadiscord-${stdenv.hostPlatform.rust.rustcTarget}";

    licenseFiles = [
      "LICENSE.md"
    ];

    meta = {
      description = "OpenAction plugin for controlling the Discord desktop client";
      homepage = "https://github.com/OpenActionPlugins/discord";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;

      authors = [
        "nekename"
      ];
    };

    passthru = {
      updateScript = mkGitHubReleaseUpdateScript {
        owner = "OpenActionPlugins";
        repo = "discord";
      };
    };
  }
)
