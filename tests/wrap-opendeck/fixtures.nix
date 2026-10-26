{
  pkgs,
  wrapOpenDeck,
}:

let
  pluginId = "test.example.sdPlugin";

  core =
    pkgs.runCommand "opendeck-wrap-test-core"
      {
        version = "0.0.0";
        meta.description = "OpenDeck wrapper test fixture";
      }
      ''
        mkdir -p "$out/bin" "$out/share/opendeck"

        cat > "$out/bin/opendeck" <<'EOF'
        #!${pkgs.runtimeShell}
        printf '%s\n' "$OPENDECK_BUNDLED_PLUGINS_DIR"
        EOF

        chmod +x "$out/bin/opendeck"
        touch "$out/share/opendeck/core-marker"
      '';

  plugin =
    pkgs.runCommand "opendeck-wrap-test-plugin"
      {
        passthru = {
          inherit pluginId;

          udev = pkgs.writeTextDir "lib/udev/rules.d/99-opendeck-wrap-test.rules" "# Test rules\n";
        };
      }
      ''
        mkdir -p "$out/${pluginId}"
        printf '{}\n' > "$out/${pluginId}/manifest.json"
      '';

  wrapped = wrapOpenDeck {
    package = core;
    plugins = [ plugin ];
    pname = "opendeck-wrap-test";
  };

in
{
  inherit
    core
    plugin
    pluginId
    wrapped
    wrapOpenDeck
    ;
}
