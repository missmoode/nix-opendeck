{
  lib,
  fetchFromGitHub,
  stdenv,
  deno,
  pkg-config,
  openssl,
  python3,
  writeShellScript,
  nix-update-script,

  mkRustOpenDeckPlugin,
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

      outputHash =
        {
          x86_64-linux = "sha256-01MuKsT8WwQPb5XNYhAdM6WcJy/6aEBREVSHTuk5dy0=";
          aarch64-linux = "sha256-AtQsrRF+tDZNnCHGozVZ4IS+USNBoquFs6+noRT9M74=";
          aarch64-darwin = "sha256-ATV6Nq8gLgji7SD+muFXYVJS4IFB0dDdMEDpca1hiYs=";
        }
        .${stdenv.hostPlatform.system};
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
    version = "0.5.1";

    src = fetchFromGitHub {
      owner = "OpenActionPlugins";
      repo = "discord";
      tag = "v${finalAttrs.version}";
      hash = "sha256-mUX0jqxsZ6kB9NrbULSfa/2KQPHisWeWNE6Q9eOaZgI=";
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

			substituteInPlace pi/svelte.config.ts \
			  --replace-fail \
			  'adapter: adapter({ pages: "../assets/pi" }),' \
			  'adapter: adapter({ pages: "../assets/pi" }), version: { name: "${finalAttrs.version}" },'
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
      platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];

      authors = [
        "nekename"
      ];
    };

    passthru = {
      inherit denoDeps;

      updatePlatformDeps = writeShellScript "${finalAttrs.pname}-update-platform-deps" ''
        exec ${python3}/bin/python3 ${../../../../lib/updateDenoDeps.py} \
          --attr "$1" \
          --package "${denoDeps.pname}" \
          --file src/packages/plugins/openactionplugins/discord/default.nix \
          --system "${stdenv.hostPlatform.system}" \
          --output "$2"
      '';

      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--use-github-releases"
          "--src-only"
        ];
      };
    };
  }
)
