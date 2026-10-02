{
  lib,
  fetchFromGitHub,
  stdenv,
  deno,
  glib,

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

      outputHash = "sha256-OR14hKH7OyeOtv0UPU8pgyUTagdsPXcw0nk6Ze2hShw=";
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
    pname = "opendeck-desktopentry";
    version = "1.0.2";

    src = fetchFromGitHub {
      owner = "OpenActionPlugins";
      repo = "desktopentry";
      tag = "v${finalAttrs.version}";
      hash = "sha256-c4c1aAqBRzE/xnfTfsHaFzSFxIXHCdQROy3fJ1g1vdc=";
    };

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    patches = [ ./patches/icon-lookup.patch ];

    postPatch = ''
      ln -s ${./Cargo.lock} Cargo.lock
      ln -s ${./deno.lock} pi/deno.lock
    '';

    nativeBuildInputs = [
      deno
    ];

    preBuild = ''
      cp -a ${denoDeps}/node_modules pi/

      cd pi
      deno task --frozen-lockfile build
      cd ..
    '';

    pluginId = "me.amankhanna.oadesktopentry.sdPlugin";
    binaryName = "oadesktopentry";

    binaryInstallPath = "oadesktopentry-${stdenv.hostPlatform.rust.rustcTarget}";

    licenseFiles = [
      "LICENSE"
    ];

    meta = {
      description = "OpenAction plugin for launching desktop applications";
      homepage = "https://github.com/OpenActionPlugins/desktopentry";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;

      authors = [
        "nekename"
      ];
    };

    runtimePackages = [
      glib
    ];

    passthru = {
      updateScript = mkGitHubReleaseUpdateScript {
        owner = "OpenActionPlugins";
        repo = "desktopentry";
      };
    };
  }
)
