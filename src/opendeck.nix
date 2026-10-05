{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch2,

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
      # Upstream fix merged after 2.14.0.
      #
      # Restrict OpenDeck's plugin WebSocket and asset servers to the loopback
      # interface instead of listening on all network interfaces.
      #
      # Remove this backport when updating to an OpenDeck release containing:
      # a4cfec6c738e5ea5d1841da9076c474a644defab
      (fetchpatch2 {
        name = "bind-plugin-servers-to-loopback.patch";
        url = "https://github.com/nekename/OpenDeck/commit/a4cfec6c738e5ea5d1841da9076c474a644defab.patch?full_index=1";

        includes = [
          "src-tauri/src/plugins/mod.rs"
          "src-tauri/src/plugins/webserver.rs"
          "src-tauri/capabilities/corsfetch.json"
          "src-tauri/tauri.conf.json"
          "src/lib/ports.ts"
        ];

        hash = "sha256-VorU93TtdvsXYWJGSAv4Vk62vwm4QKLC2kEn8pMlFHc=";
      })

      # Allow the local asset webserver to serve files through symlinked plugin
      # directories, while retaining its path-containment checks.
      #
      # Requests must still originate through a specific plugin entry under
      # OpenDeck's plugin directory, and the requested file must canonicalize
      # beneath that plugin's canonical target.
      ./patches/opendeck/0001-support-symlinked-plugin-assets.patch

      # Preserve plugin directory symlinks instead of replacing them with their
      # resolved targets.
      #
      # Normal filesystem access already follows the symlink when reading plugin
      # contents, while retaining the lexical plugin path preserves plugin IDs and
      # ensures asset URLs continue to pass through OpenDeck's plugin directory.
      ./patches/opendeck/0002-preserve-symlinked-plugin-paths.patch

      # Avoid rewriting Unix permissions when a plugin executable is already
      # executable.
      #
      # This allows executables stored in immutable locations such as the Nix
      # store to be used without attempting to chmod them.
      ./patches/opendeck/0003-avoid-redundant-plugin-chmod.patch

      # Support an optional externally-managed-plugins file in OpenDeck's config
      # directory.
      #
      # Plugin IDs listed in that file cannot be replaced or removed through
      # OpenDeck's plugin manager. If the file is absent or unreadable, OpenDeck
      # retains the normal upstream behaviour.
      #
      # This is a downstream functionality used by nix-opendeck,
      ./patches/opendeck/0004-protect-externally-managed-plugins.patch
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

      # Identify this as the nix-opendeck build without maintaining another
      # source patch solely for the build-info string.
      substituteInPlace src-tauri/src/events/frontend/settings.rs \
        --replace-fail \
        'built_info::PKG_VERSION,' \
        'format!("{}+nix", built_info::PKG_VERSION),'

      substituteInPlace "$cargoDepsCopy"/*/libappindicator-sys-*/src/lib.rs \
        --replace-fail \
        'libayatana-appindicator3.so.1' \
        '${libayatana-appindicator}/lib/libayatana-appindicator3.so.1'
    '';

    cargoHash = "sha256-AZ32cl5qbq/lROow9CpBgl3eztLos7VMqOnQV4kdvJU=";

    cargoRoot = "src-tauri";
    buildAndTestSubdir = finalAttrs.cargoRoot;

    nativeBuildInputs = [
      cargo-tauri.hook
      deno
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      wrapGAppsHook4
    ];

    preBuild = ''
      export DENO_DIR="$TMPDIR/deno-cache"

      cp -a ${denoDeps}/. node_modules/

      mkdir -p "${finalAttrs.cargoRoot}/target/plugins"

      ${lib.concatMapStringsSep "\n" (plugin: ''
        cp -a --no-preserve=mode \
          "${plugin}/." \
          "${finalAttrs.cargoRoot}/target/plugins/"
      '') bundledPlugins}

      chmod -R u+rwX "${finalAttrs.cargoRoot}/target/plugins"
    '';

    postInstall = ''
      install -Dm644 \
        ${finalAttrs.cargoRoot}/bundle/40-streamdeck.rules \
        "$out/lib/udev/rules.d/40-streamdeck.rules"

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
      )
    '';

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
