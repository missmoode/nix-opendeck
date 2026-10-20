{
  lib,
  fetchFromGitHub,
  stdenv,
  deno,
  glib,
  makeWrapper,
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

      outputHash = "sha256-gk0lz/CXwyc0o9Txggu3qSk/WTN3KlQDiOXEgCaKC2U=";
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
    pname = "opendeck-openactionplugins-desktopentry";
    version = "1.0.3";

    src = fetchFromGitHub {
      owner = "OpenActionPlugins";
      repo = "desktopentry";
      tag = "v${finalAttrs.version}";
      hash = "sha256-OOsQzT0rvE3HDgTprs5rcM/As5WO8tafFKoSAyP2mZg=";
    };

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    patches = [
      ./patches/icon-lookup.patch
      ./patches/stable-desktop-entry-id.patch
    ];

    postPatch = ''
      ln -s ${./Cargo.lock} Cargo.lock
      ln -s ${./deno.lock} pi/deno.lock
    '';
    nativeBuildInputs = [
      deno
      makeWrapper
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

    postInstall = ''
      wrapProgram "$out/${finalAttrs.pluginId}/${finalAttrs.binaryInstallPath}" \
        --prefix PATH : "${glib}/bin"
    '';

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

    passthru = {
      inherit denoDeps;

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
