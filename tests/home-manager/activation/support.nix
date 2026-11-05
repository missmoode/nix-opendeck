{
  pkgs,
  homeManager,
  module,
}:

let
  lib = pkgs.lib;
  testHome = "/__opendeck_hm_activation_test_home__";

  mkPlugin =
    pluginId: version:
    pkgs.runCommand "opendeck-hm-test-plugin-${version}"
      {
        passthru = { inherit pluginId; };
      }
      ''
        mkdir -p "$out/${pluginId}"
        printf '%s\n' '{"Name":"Test plugin","Version":"${version}","Actions":[]}' \
          > "$out/${pluginId}/manifest.json"
      '';

  # The fake launcher only records notifications; it never starts OpenDeck.
  fakeOpenDeck = pkgs.writeShellScriptBin "opendeck" ''
    printf '%s\n' "$*" >> "$OPENDECK_TEST_LOG"
  '';

  mkActivation =
    options:
    let
      hm = homeManager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          module
          {
            home.username = "test";
            home.homeDirectory = testHome;
            home.stateVersion = "26.05";
            programs.opendeck = {
              enable = true;
              installPackage = false;
              package = fakeOpenDeck;
            }
            // options;
          }
        ];
      };
    in
    pkgs.writeText "opendeck-hm-activation-script" hm.config.home.activation.opendeck.data;
in
{
  inherit
    lib
    mkPlugin
    mkActivation
    fakeOpenDeck
    ;

  managedId = "test.managed.sdPlugin";
  otherId = "test.other.sdPlugin";
  userId = "test.user.sdPlugin";

  nativeBuildInputs = with pkgs; [
    bash
    coreutils
    gnugrep
    gnused
    jq
  ];

  # Run the *generated production activation* in a writable fake HOME.
  # Only the D-Bus query and launcher are mocked, not the reconciliation.
  setup = ''
    set -euo pipefail
    root="$TMPDIR/opendeck-hm-test"
    home="$root/home"
    mkdir -p "$root" "$home"
    ${
      if pkgs.stdenv.hostPlatform.isDarwin then
        ''configDir="$home/Library/Application Support/opendeck"''
      else
        ''configDir="$home/.config/opendeck"''
    }
    pluginDir="$configDir/plugins"
    state="$configDir/externally-managed-plugins"
    settingsFile="$configDir/settings.json"
    export OPENDECK_TEST_LOG="$root/opendeck-commands.log"
    export OPENDECK_TEST_DBUS=true

    cat > "$root/mock-gdbus" <<'END_GDBUS'
    #!${lib.getExe pkgs.bash}
    if [[ "$OPENDECK_TEST_DBUS" == true ]]; then
      printf '(true,)\n'
    else
      printf '(false,)\n'
    fi
    END_GDBUS
    chmod +x "$root/mock-gdbus"
    [[ "$("$root/mock-gdbus" call)" == '(true,)' ]]
    [[ "$(OPENDECK_TEST_DBUS=false "$root/mock-gdbus" call)" == '(false,)' ]]

    render() {
      {
        printf '%s\n' 'set -euo pipefail' 'verboseEcho() { :; }'
        sed \
          -e 's|${testHome}|'"$home"'|g' \
          -e 's|${lib.getExe' pkgs.glib "gdbus"}|'"$root/mock-gdbus"'|g' \
          "$1"
      } > "$2"
      bash -n "$2"
    }

    expect_link() {
      if [[ ! -L "$1" || "$(readlink "$1")" != "$2" ]]; then
        echo "Incorrect managed plugin symlink: $1 (expected $2)" >&2
        exit 1
      fi
    }

    expect_failure() {
      if bash "$1" > "$root/expected-failure.log" 2>&1; then
        echo "Expected activation to fail: $1" >&2
        exit 1
      fi
    }

    expect_commands() {
      local actual=""
      if [[ -f "$OPENDECK_TEST_LOG" ]]; then
        actual=$(cat "$OPENDECK_TEST_LOG")
      fi
      if [[ "$actual" != "$1" ]]; then
        printf 'Unexpected OpenDeck commands: <%s>; expected <%s>\n' "$actual" "$1" >&2
        exit 1
      fi
    }

    reset_state() {
      rm -rf "$configDir"
      rm -f "$OPENDECK_TEST_LOG"
    }
  '';
}
