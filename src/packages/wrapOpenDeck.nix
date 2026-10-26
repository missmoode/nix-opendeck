{
  lib,
  stdenvNoCC,
  linkFarm,
  symlinkJoin,
  makeWrapper,
  runCommand,
  rcodesign,
}:
{
  package,
  plugins ? [ ],
  pname ? "opendeck",
}:

let
  pluginIds = map (plugin: plugin.pluginId) plugins;

  duplicateIds = lib.filter (id: lib.count (other: other == id) pluginIds > 1) (lib.unique pluginIds);

  # Linux only: a directory of links to plugin packages.
  # OpenDeck loads these directly from the Nix store without copying them
  # into its writable plugin directory.
  pluginBundle = linkFarm "${pname}-bundled-plugins" (
    map (plugin: {
      name = plugin.pluginId;
      path = "${plugin}/${plugin.pluginId}";
    }) plugins
  );

  passthru = {
    bundledPluginIds = pluginIds;
  }
  # Let wrapped packages expose the core's dependency updater.
  // lib.optionalAttrs (package ? updatePlatformDeps) {
    inherit (package) updatePlatformDeps;
  }
  // lib.optionalAttrs (package ? denoDeps) {
    inherit (package) denoDeps;
  }
  // lib.optionalAttrs stdenvNoCC.hostPlatform.isLinux {
    udev = symlinkJoin {
      name = "${pname}-udev-rules-${package.version}";

      paths =
        (lib.optional (package ? udev) package.udev)
        ++ map (plugin: plugin.udev) (lib.filter (plugin: plugin ? udev) plugins);
    };
  };

  commonAttrs = {
    inherit pname passthru;
    version = package.version;
    meta = package.meta;
  };

  # Fail when a caller passes malformed plugin packages.
  validatePlugins = lib.concatMapStringsSep "\n" (plugin: ''
    if [ ! -f ${lib.escapeShellArg "${plugin}/${plugin.pluginId}/manifest.json"} ]; then
      echo "wrapOpenDeck: missing manifest.json in ${plugin.pname or plugin.pluginId}" >&2
      exit 1
    fi
  '') plugins;

in

assert lib.assertMsg (
  duplicateIds == [ ]
) "wrapOpenDeck: duplicate plugin IDs: ${lib.concatStringsSep ", " duplicateIds}";

assert lib.assertMsg (
  (package.bundledPluginIds or [ ]) == [ ]
) "wrapOpenDeck: package must be an unbundled OpenDeck core";

if stdenvNoCC.hostPlatform.isDarwin then
  runCommand "${pname}-${package.version}"
    (
      commonAttrs
      // {
        nativeBuildInputs = [ rcodesign ];
      }
    )
    ''
      mkdir -p "$out/Applications" "$out/bin"

      # Keep the native macOS application structure and executable.
      cp -R \
        "${package}/Applications/OpenDeck.app" \
        "$out/Applications/"

      app="$out/Applications/OpenDeck.app"
      pluginDir="$app/Contents/Resources/plugins"

      chmod -R u+w "$app"
      mkdir -p "$pluginDir"

      ${validatePlugins}

      ${lib.concatMapStringsSep "\n" (plugin: ''
        pluginId=${lib.escapeShellArg plugin.pluginId}
        source=${lib.escapeShellArg "${plugin}/${plugin.pluginId}"}
        destination="$pluginDir/$pluginId"

        mkdir -p "$destination"

        # Materialize symlinks instead of placing external Nix store
        # symlinks inside the signed application bundle.
        cp -RL "$source/." "$destination/"
      '') plugins}

      # Copied plugin binaries must be writable for code signing.
      chmod -R u+w "$pluginDir"

      # A CLI entry point without replacing the native .app executable.
      ln -s \
        ../Applications/OpenDeck.app/Contents/MacOS/opendeck \
        "$out/bin/opendeck"

      # Bundled resources have changed: sign the final composed app.
      rcodesign sign \
        --code-signature-flags runtime \
        "$app"
    ''

else if stdenvNoCC.hostPlatform.isLinux then
  symlinkJoin (
    commonAttrs
    // {
      paths = [ package ];
      nativeBuildInputs = [ makeWrapper ];

      postBuild = ''
        ${validatePlugins}

        # lndir has linked the original core launcher here.
        # Replace only the launcher, retaining desktop files,
        # icons, libraries and other core package contents.
        rm "$out/bin/opendeck"

        makeWrapper \
          "${package}/bin/opendeck" \
          "$out/bin/opendeck" \
          --set OPENDECK_BUNDLED_PLUGINS_DIR "${pluginBundle}"
      '';
    }
  )

else
  throw "wrapOpenDeck: unsupported platform"
