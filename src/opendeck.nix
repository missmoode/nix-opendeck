{
  lib,
  stdenv,
  rcodesign,
  fetchFromGitHub,
  nix-update-script,
  python3,
  writeShellScript,

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

  bundledPlugins ? [ ],
  pname ? "opendeck-core",
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
    pname = pname;

    version = "2.14.2";

    src = fetchFromGitHub {
      owner = "nekename";
      repo = "OpenDeck";
      tag = "v${finalAttrs.version}";
      hash = "sha256-DNgOH5d7c4Y6y8Wz8Bcc8/I3S9IAyLav4OfKgwT/i/c=";
    };

    patches = [

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

      # Preserve Nix wrapper-provided runtime paths when OpenDeck reconstructs
      # PATH from the user's login shell. Perform environment initialization
      # before starting Tokio's multithreaded runtime.
      ./patches/opendeck/0005-preserve-wrapper-path.patch

      # Direct users of the Nix build to nix-opendeck's plugin
      # compatibility documentation before reporting upstream issues.
      ./patches/opendeck/0006-nix-plugin-store-warning.patch

      # Explain the PATH requirement for OpenDeck's built-in Linux autostart.
      # The autostart toggle and settings behaviour remain unchanged.
      ./patches/opendeck/0007-document-nix-autostart-path.patch
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
          -d "$cargoDepsCopy"/*/tauri-plugin-autostart-2.5.1 \
          < ${./patches/tauri-plugin-autostart/0001-use-path-for-linux-autostart.patch}
      ''}

      # On macOS, prefer a stable Nix profile path when it points to the
      # running OpenDeck executable. Otherwise retain upstream behaviour.
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        patch -p1 \
          -d "$cargoDepsCopy"/*/tauri-plugin-autostart-2.5.1 \
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
      export DENO_DIR="$TMPDIR/deno-cache"

      cp -a ${denoDeps}/. node_modules/

      mkdir -p "${finalAttrs.cargoRoot}/target/plugins"

      ${lib.concatMapStringsSep "\n" (plugin: ''
        cp -R \
          "${plugin}/." \
          "${finalAttrs.cargoRoot}/target/plugins/"
      '') bundledPlugins}

      chmod -R u+rwX "${finalAttrs.cargoRoot}/target/plugins"
    '';

    postInstall =
      lib.optionalString stdenv.hostPlatform.isLinux ''
        install -Dm644 \
          ${finalAttrs.cargoRoot}/bundle/40-streamdeck.rules \
          "$out/lib/udev/rules.d/40-streamdeck.rules"
      ''
      + ''
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

      bundledPluginIds = map (plugin: plugin.pluginId) bundledPlugins;

      # Native CI runs this optional hook before building the package. The
      # hook updates only this host's hash if the Deno dependency FOD changed.
      updatePlatformDeps = writeShellScript "${finalAttrs.pname}-update-platform-deps" ''
        exec ${python3}/bin/python3 ${./lib/updateDenoDeps.py} \
          --attr "$1" \
          --package "${denoDeps.pname}" \
          --file src/opendeck.nix \
          --system "${stdenv.hostPlatform.system}" \
          --output "$2"
      '';

      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--use-github-releases"
        ];
      };
    };
  }
)
