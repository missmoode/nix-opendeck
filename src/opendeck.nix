{
  lib,
  stdenv,
  fetchFromGitHub,

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
  libayatana-appindicator,

  gst_all_1,

  bundledPlugins ? [ ],
  pname ? "opendeck-core",
  updateScript ? null,
}:
# Make sure we're not bundling the same plugin multiple times
let
  bundledPluginIds = map (plugin: plugin.pluginId) bundledPlugins;

  duplicateBundledPluginIds = lib.filter (
    pluginId: lib.count (id: id == pluginId) bundledPluginIds > 1
  ) (lib.unique bundledPluginIds);

  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
  ];

  gstPluginPath = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins;
in
assert duplicateBundledPluginIds == [ ];
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

      outputHash = "sha256-J3mIc+eF6ET07BV5x39yw0p2E2JZCAArOJKxrqqhcDk=";
      outputHashMode = "recursive";
    };
  in
  {
    pname = pname;

    version = "2.14.0";

    src = fetchFromGitHub {
      owner = "nekename";
      repo = "OpenDeck";
      tag = "v${finalAttrs.version}";
      hash = "sha256-2zI1asMPLxllKaDaCaGbIZ1PwiQJCCsiuyG/gUKe0Mk=";
    };

    patches = [
      ./patches/opendeck/0001-fix-plugin-webserver-path-check.patch
      ./patches/opendeck/0002-support-symlinked-plugin-executables.patch
      ./patches/opendeck/0003-protect-home-manager-plugins.patch
      ./patches/opendeck/0004-identify-nix-build.patch
    ];

    postPatch = ''
      rm -rf plugins
      mkdir plugins

      substituteInPlace "$cargoDepsCopy"/*/libappindicator-sys-*/src/lib.rs \
        --replace-fail \
        'libayatana-appindicator3.so.1' \
        '${libayatana-appindicator}/lib/libayatana-appindicator3.so.1'
    '';

    cargoHash = "sha256-AZ32cl5qbq/lROow9CpBgl3eztLos7VMqOnQV4kdvJU=";

    # Identify location of cargo project
    cargoRoot = "src-tauri";
    buildAndTestSubdir = finalAttrs.cargoRoot;

    # Packages used to run the build (similar to devdependencies in npm?)
    nativeBuildInputs = [
      cargo-tauri.hook
      deno
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      wrapGAppsHook4
    ];

    # Install using the dependencies we downloaded earlier
    #  Copy them over and make them writable so that deno can modify
    #  as it builds if needed
    preBuild = ''
      cp -a ${denoDeps}/. node_modules/

      mkdir -p "${finalAttrs.cargoRoot}/target/plugins"

      ${lib.concatMapStringsSep "\n" (plugin: ''
        cp -a ${plugin}/. "${finalAttrs.cargoRoot}/target/plugins/"
      '') bundledPlugins}

      chmod -R u+rwX "${finalAttrs.cargoRoot}/target/plugins"
    '';

    # Install udev rules
    postInstall = ''
      install -Dm644 \
        ${finalAttrs.cargoRoot}/bundle/40-streamdeck.rules \
        "$out/lib/udev/rules.d/40-streamdeck.rules"

      install -Dm644 \
        "${finalAttrs.src}/LICENSE.md" \
        "$out/share/licenses/${finalAttrs.pname}/LICENSE.md"
    '';

    # Tools needed to perform the nix build
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

    # Explicitly expose the GStreamer plugin directories to WebKit.
    # WebKitWebProcess otherwise may fail when attempting HTML audio
    # playback on NixOS.
    preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      gappsWrapperArgs+=(
        --set GST_PLUGIN_PATH_1_0 "${gstPluginPath}"
      )
    '';

    # Debian bundle contains all the important linux integration files.
    tauriBundleType = "deb";

    meta = {
      description = "Linux software for your Elgato Stream Deck";
      homepage = "https://github.com/nekename/OpenDeck";
      license = lib.licenses.gpl3Plus;

      authors = [
        "nekename"
      ];

      mainProgram = "opendeck";
      platforms = lib.platforms.linux;
    };

    passthru = {
      bundledPluginIds = map (plugin: plugin.pluginId) bundledPlugins;
    }
    // lib.optionalAttrs (updateScript != null) {
      inherit updateScript;
    };
  }
)
