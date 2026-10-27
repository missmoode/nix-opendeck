{
  lib,
  stdenv,
  rcodesign,
  fetchFromGitHub,
  nix-update-script,
  python3,
  writeShellScript,
  runCommand,

  rustPlatform,
  cargo-tauri,

  deno,
  pkg-config,

  udev,
  dbus,
  glib-networking,
  openssl,
  webkitgtk_4_1,
  wrapGAppsHook4,
  nodejs,
  libayatana-appindicator,

  gst_all_1,
}:
let
  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
  ];

  gstPluginPath = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins;
in
rustPlatform.buildRustPackage (
  finalAttrs:
  let
    denoDeps = stdenv.mkDerivation {
      pname = "opendeck-deno-deps";
      version = finalAttrs.version;
      src = finalAttrs.src;

      nativeBuildInputs = [ deno ];

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        export DENO_DIR="$TMPDIR/deno"

        deno ci

        mkdir -p "$out"
        cp -a node_modules/. "$out/"

        runHook postInstall
      '';

      outputHash =
        {
          x86_64-linux = "sha256-5iMi4aJMXQEeq8TF1kvxLrSTnC2y9m3G3FSb2PVeA9w=";
          aarch64-linux = "sha256-6SM1uH4aWYEUBPJ0NHOQy5Q48FtedoNnRm2eSZ1OjTw=";
          aarch64-darwin = "sha256-NtGQvJv53Y0cShi6ZBg9lBKgiGMQZnbaHpBZlMmodFs=";
        }
        .${stdenv.hostPlatform.system};
      outputHashMode = "recursive";
    };
  in
  {
    pname = "opendeck-core";

    version = "2.14.2";

    src = fetchFromGitHub {
      owner = "nekename";
      repo = "OpenDeck";
      tag = "v${finalAttrs.version}";
      hash = "sha256-DNgOH5d7c4Y6y8Wz8Bcc8/I3S9IAyLav4OfKgwT/i/c=";
    };

    patches = [
      # Define shared source resolution and ownership before their consumers.
      ./patches/0001-plugin-source-helpers.patch

      # Permit already-executable plugins in immutable locations.
      ./patches/0002-read-only-plugin-executables.patch

      # Authorize plugin assets using lexical roots and canonical containment.
      ./patches/0003-plugin-asset-authorization.patch

      # Load selected sources directly and resolve resources/profile paths.
      ./patches/0004-direct-plugin-loading.patch

      # Guard backend mutations and preserve data when effective sources change.
      ./patches/0005-managed-plugin-backend.patch

      # List effective plugins via the upstream GUI's existing builtin field.
      ./patches/0006-effective-plugin-listing.patch

      # Back up user plugin files, excluding links and declarative ownership.
      ./patches/0007-managed-plugin-backups.patch

      # Keep the current HM links and ownership when restoring user data.
      ./patches/0008-protect-managed-plugin-restore.patch

      # Reload or restart a running instance without opening an inactive one.
      ./patches/0009-running-instance-commands.patch

      # Preserve portable encoder resources when saving and loading profiles.
      ./patches/0010-persist-encoder-resource-paths.patch

      # Preserve wrapper-provided runtime paths when importing the login shell.
      ./patches/0011-preserve-wrapper-path.patch

      # Point Nix users to plugin compatibility information.
      ./patches/0012-nix-plugin-store-warning.patch

      # Explain the stable launcher PATH requirement for Nix autostart.
      ./patches/0013-document-nix-autostart-path.patch
    ];

    postPatch = ''
      rm -rf plugins
      mkdir plugins

      # SvelteKit defaults version.name to Date.now(), which makes the generated
      # frontend — and therefore Tauri's embedded resources — non-reproducible.
      # Prior art: https://github.com/Kitt3120/opendeck-nix
      substituteInPlace svelte.config.ts \
        --replace-fail \
        'adapter: adapter(),' \
        'adapter: adapter(), version: { name: "${finalAttrs.version}" },'

      # Identify this as the nix-opendeck build and replace the unavailable
      # upstream Git commit hash with a Nix-specific build identifier.
      substituteInPlace src-tauri/src/events/frontend/settings.rs \
        --replace-fail \
        'built_info::PKG_VERSION,' \
        'format!("{}+nix", built_info::PKG_VERSION),' \
        --replace-fail \
        'built_info::GIT_COMMIT_HASH_SHORT.unwrap_or("commit hash unknown"),' \
        '"built via nix-opendeck",'

      # Use nix-patched libayatana
      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        substituteInPlace "$cargoDepsCopy"/*/libappindicator-sys-*/src/lib.rs \
          --replace-fail \
          'libayatana-appindicator3.so.1' \
          '${libayatana-appindicator}/lib/libayatana-appindicator3.so.1'
      ''}

      # Prevent Linux autostart entries from referencing generation-specific
      # Nix store paths. Resolve the installed launcher through PATH instead.
      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        patch -p1 \
          -d "$cargoDepsCopy"/*/tauri-plugin-autostart-* \
          < ${./patches/tauri-plugin-autostart/0001-use-path-for-linux-autostart.patch}
      ''}

      # On macOS, prefer a stable Nix profile path when it points to the
      # running OpenDeck executable. Otherwise retain upstream behaviour.
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        patch -p1 \
          -d "$cargoDepsCopy"/*/tauri-plugin-autostart-* \
          < ${./patches/tauri-plugin-autostart/0002-use-profile-path-for-macos-autostart.patch}
      ''}
    '';

    cargoHash = "sha256-IVkeIHrQvZxZ0bPuCItCs5a0yxWrz0dcWmjIg5BFoi8=";

    cargoRoot = "src-tauri";
    buildAndTestSubdir = finalAttrs.cargoRoot;
    # Sign the completed macOS bundle after Nix's fixup phase instead.
    tauriBuildFlags = lib.optionals stdenv.hostPlatform.isDarwin [
      "--no-sign"
    ];

    nativeBuildInputs = [
      cargo-tauri.hook
      deno
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      wrapGAppsHook4
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      rcodesign
    ];

    preBuild = ''
      # Rust embeds absolute paths to vendored dependencies in the macOS
      # executable. Remap Nix's variable build directory to a stable path.
      #
      # Setting RUSTFLAGS overrides Cargo's target rustflags, so explicitly
      # retain the frame-pointer setting supplied by Nixpkgs.
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        # Rust source paths.
        export RUSTFLAGS="''${RUSTFLAGS:+$RUSTFLAGS }-Cforce-frame-pointers=yes --remap-path-prefix=$NIX_BUILD_TOP=/build -C link-arg=-Wl,-S"

        # C/C++ source paths, including those compiled by aws-lc-sys.
        export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:+$NIX_CFLAGS_COMPILE }-ffile-prefix-map=$NIX_BUILD_TOP=/build"
      ''}


      export DENO_DIR="$TMPDIR/deno-cache"

      cp -a ${denoDeps}/. node_modules/

      # Tauri expects this resource directory, even when it is empty.
      mkdir -p "${finalAttrs.cargoRoot}/target/plugins"
    '';

    postInstall = ''
      install -Dm644 \
        "${finalAttrs.src}/LICENSE.md" \
        "$out/share/licenses/${finalAttrs.pname}/LICENSE.md"
    '';

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux (
      gstPlugins
      ++ [
        dbus
        glib-networking
        libayatana-appindicator
        openssl
        udev
        webkitgtk_4_1
      ]
    );

    preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      gappsWrapperArgs+=(
        --set GST_PLUGIN_PATH_1_0 "${gstPluginPath}"
        --prefix PATH : "${lib.makeBinPath [ nodejs ]}"
      )
    '';

    postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
      rcodesign sign \
        --code-signature-flags runtime \
        "$out/Applications/OpenDeck.app"
    '';

    meta = {
      description = "Open-source software for Elgato Stream Deck devices (and similar)";
      homepage = "https://github.com/nekename/OpenDeck";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];

      authors = [
        "nekename"
      ];

      mainProgram = "opendeck";
    };

    passthru = {
      inherit denoDeps;

      bundledPluginIds = [ ];

      # Native CI runs this optional hook before building the package. The
      # hook updates only this host's hash if the Deno dependency FOD changed.
      updatePlatformDeps = writeShellScript "${finalAttrs.pname}-update-platform-deps" ''
        exec ${python3}/bin/python3 ${../../lib/updateDenoDeps.py} \
          --attr "$1" \
          --package "${denoDeps.pname}" \
          --file src/packages/opendeck/default.nix \
          --system "${stdenv.hostPlatform.system}" \
          --output "$2"
      '';

      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--use-github-releases"
        ];
      };
    }
    // lib.optionalAttrs stdenv.hostPlatform.isLinux {
      udev = runCommand "opendeck-core-udev-rules-${finalAttrs.version}" { } ''
        install -Dm644 \
          "${finalAttrs.src}/src-tauri/bundle/40-streamdeck.rules" \
          "$out/lib/udev/rules.d/40-streamdeck.rules"
      '';
    };
  }
)
