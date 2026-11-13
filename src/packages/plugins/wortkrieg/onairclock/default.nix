{
  lib,
  stdenv,
  fetchFromGitHub,
  jq,
  nix-update-script,

  mkNpmOpenDeckPlugin,
}:

mkNpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-wortkrieg-onairclock";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "wortkrieg";
    repo = "streamdeck-onairclock";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ezFjvJ6eSW/3UMIVhb/aJKG+yutDEy/k9OTebDdpJdA=";
  };

  npmDepsHash = "sha256-8qI5YcKVlLjkT/rwq/v7CZ32rFHC5n9uHzbHMhKSTSA=";

  pluginId = "fail.marc.onairclock.sdPlugin";
  pluginDir = finalAttrs.pluginId;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    npm test

    runHook postCheck
  '';

  # The Elgato SDK writes logs under $PWD/logs, which is read-only
  # when the plugin is installed in the Nix store.
  # Redirect only SDK logging; preserve CWD for resource lookups.
  preBuild = ''
        sdkRoot="node_modules/@elgato/streamdeck"

        if [ ! -d "$sdkRoot/dist" ]; then
          echo "error: Elgato SDK dist directory not found" >&2
          exit 1
        fi

        # Use portable find/grep rather than GNU-specific grep --include.
        mapfile -t sdkLoggers < <(
          find "$sdkRoot/dist" -type f -name '*.js' \
            -exec grep -lF \
              'dest: path.join(cwd(), "logs"),' {} +
        )

        if [ "''${#sdkLoggers[@]}" -ne 1 ]; then
          echo "error: expected exactly one Elgato SDK logger; found ''${#sdkLoggers[@]}" >&2
          exit 1
        fi

        sdkLogger="''${sdkLoggers[0]}"

        # Avoid editing linked dependency-cache files.
        cp -L "$sdkLogger" "$sdkLogger.nix"
        mv -f "$sdkLogger.nix" "$sdkLogger"

        substituteInPlace "$sdkLogger" \
          --replace-fail \
            'import path from "node:path";' \
            'import path from "node:path";
    import fs from "node:fs";
    import { homedir } from "node:os";' \
          --replace-fail \
            'dest: path.join(cwd(), "logs"),' \
            'dest: (() => {
          const stateHome = process.env.XDG_STATE_HOME;

          const logs = process.platform === "darwin"
            ? path.join(
                homedir(), "Library", "Logs",
                "OpenDeck", "plugins", getPluginUUID()
              )
            : path.join(
                stateHome && path.isAbsolute(stateHome)
                  ? stateHome
                  : path.join(homedir(), ".local", "state"),
                "opendeck", "plugins", getPluginUUID(), "logs"
              );

          fs.mkdirSync(logs, { recursive: true, mode: 0o700 });
          fs.chmodSync(logs, 0o700);

          return logs;
        })(),'
  '';

  # Upstream supports macOS and Windows. Enable native Linux execution
  # through OpenDeck's existing Node.js plugin support.
  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    test -s "$plugin/bin/plugin.js"
    test -f "$plugin/bin/package.json"

    ${jq}/bin/jq \
      '.OS += [{"Platform": "linux"}]' \
      "$plugin/manifest.json" > "$plugin/manifest.json.new"

    mv "$plugin/manifest.json.new" "$plugin/manifest.json"
  '';

  licenseFiles = [
    "LICENSE"
  ];

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Broadcast-inspired clocks, time zones, and countdowns for OpenDeck";
    homepage = "https://github.com/wortkrieg/streamdeck-onairclock";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };
})
