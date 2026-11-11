{
  lib,
  fetchFromGitHub,
  nix-update-script,

  mkPnpmOpenDeckPlugin,
}:

mkPnpmOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-tonyheadband-steam";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "TonyHeadband";
    repo = "opendeck-steam-plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Fiu8jFQ7wQULdFYB9nlud1qt1OPAYhJx+cdpFvz3AqI=";
  };

  pnpmDepsHash = "sha256-zWqRrys7OtvAqFpdYpUjmR6L3Bs+A6mLTchqq0cBonI=";

  pluginId = "io.github.tonyheadband.opendeck-steam.sdPlugin";
  pluginDir = finalAttrs.pluginId;

  # The Elgato SDK unconditionally writes logs under $PWD/logs. Keep the
  # original CWD for plugin/SDK resource lookups; redirect only SDK logging.
  # Patch the installed SDK, not the fetched source or the pnpm dependency store.
  preBuild = ''
        # pnpm installs a version-independent package symlink. The SDK may
        # publish its logger in different dist/ files, so find the file containing
        # the known implementation rather than assuming a path or package version.
        sdkRoot="$(readlink -f node_modules/@elgato/streamdeck)"
        if [ ! -d "$sdkRoot/dist" ]; then
          echo "error: Elgato SDK dist directory not found: $sdkRoot/dist" >&2
          exit 1
        fi

        mapfile -t sdkLoggers < <(
          grep -rlF --include='*.js' 'dest: path.join(cwd(), "logs"),' "$sdkRoot/dist" || true
        )
        if [ "''${#sdkLoggers[@]}" -ne 1 ]; then
          echo "error: expected exactly one Elgato SDK logger implementation; found ''${#sdkLoggers[@]}" >&2
          find "$sdkRoot/dist" -name '*.js' -print >&2
          exit 1
        fi
        sdkLogger="''${sdkLoggers[0]}"

        # pnpm may link installed files to a shared dependency store. Break that
        # link before editing, so only this build's copy gets patched.
        cp -L "$sdkLogger" "$sdkLogger.nix"
        mv -f "$sdkLogger.nix" "$sdkLogger"

        substituteInPlace "$sdkLogger" \
          --replace-fail 'import path from "node:path";' 'import path from "node:path";
    import fs from "node:fs";
    import { homedir } from "node:os";' \
          --replace-fail 'dest: path.join(cwd(), "logs"),' 'dest: (() => {
      const configuredStateHome = process.env.XDG_STATE_HOME;
      const stateHome = configuredStateHome && path.isAbsolute(configuredStateHome)
        ? configuredStateHome
        : path.join(homedir(), ".local", "state");
      const logs = path.join(stateHome, "opendeck", "plugins", getPluginUUID(), "logs");
      fs.mkdirSync(logs, { recursive: true, mode: 0o700 });
      fs.chmodSync(logs, 0o700);
      return logs;
    })(),'
  '';

  requiredCommands = [ "xdg-open" ];
  licenseFiles = [ "LICENSE" ];

  meta = {
    description = "Control the Steam client, games, and friend presence from OpenDeck";
    homepage = "https://github.com/TonyHeadband/opendeck-steam-plugin";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
