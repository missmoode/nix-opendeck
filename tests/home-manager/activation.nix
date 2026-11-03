{
  pkgs,
  homeManager,
  module,
  core,
}:

let
  # Replaced with a private, writable directory when the test runs.
  # This allows the same evaluated activation code to run on Linux and Darwin.
  testHome = "/__opendeck_hm_activation_test_home__";

  managedId = "test.managed.sdPlugin";
  otherId = "test.other.sdPlugin";
  userId = "test.user.sdPlugin";

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

  old = mkPlugin managedId "old";
  new = mkPlugin managedId "new";
  other = mkPlugin otherId "other";

  # A declared package whose advertised plugin directory is absent.
  missing =
    pkgs.runCommand "opendeck-hm-test-plugin-missing"
      {
        passthru.pluginId = managedId;
      }
      ''
        mkdir -p "$out"
      '';

  mkActivation =
    plugins:
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
              package = core;
              inherit plugins;

              # Only filesystem reconciliation is under test.
              reloadOnPluginChanges = false;
            };
          }
        ];
      };
    in
    pkgs.writeText "opendeck-hm-activation" hm.config.home.activation.opendeckPlugins.data;

  initial = mkActivation [ old ];
  upgraded = mkActivation [ new ];
  removed = mkActivation [ ];
  conflicting = mkActivation [
    new
    other
  ];
  invalid = mkActivation [ missing ];
in
pkgs.runCommand "opendeck-home-manager-activation"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    set -euo pipefail

    root="$TMPDIR/opendeck-hm-activation"
    home="$root/home"
    mkdir -p "$root"

    ${
      if pkgs.stdenv.hostPlatform.isDarwin then
        ''
          configDir="$home/Library/Application Support/opendeck"
        ''
      else
        ''
          configDir="$home/.config/opendeck"
        ''
    }

    pluginDir="$configDir/plugins"
    state="$configDir/externally-managed-plugins"
    managed="$pluginDir/${managedId}"
    otherTarget="$pluginDir/${otherId}"
    userTarget="$pluginDir/${userId}"

    # Execute the actual generated Home Manager activation code.
    # Only the logging helper from its normal activation environment is stubbed.
    render() {
      {
        printf '%s\n' 'set -euo pipefail' 'verboseEcho() { :; }'
        sed 's|${testHome}|'"$home"'|g' "$1"
      } > "$2"
    }

    render ${initial} "$root/initial.sh"
    render ${upgraded} "$root/upgraded.sh"
    render ${removed} "$root/removed.sh"
    render ${conflicting} "$root/conflicting.sh"
    render ${invalid} "$root/invalid.sh"

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

    expect_ownership_unchanged() {
      if ! cmp -s "$root/initial-ownership" "$state"; then
        echo "Activation unexpectedly changed plugin ownership state" >&2
        exit 1
      fi
    }

    expect_user_plugins_untouched() {
      [[ "$(cat "$userTarget/settings.json")" == 'user data' ]]
      if [[ -e "$otherTarget" ]]; then
        [[ "$(cat "$otherTarget/settings.json")" == 'do not overwrite' ]]
      fi
    }

    # A plugin installed through OpenDeck's GUI must survive reconciliation.
    mkdir -p "$userTarget"
    printf '%s\n' 'user data' > "$userTarget/settings.json"

    # Dry runs must not create an installation or ownership state.
    DRY_RUN=1 bash "$root/initial.sh"
    [[ ! -e "$managed" && ! -L "$managed" && ! -e "$state" ]]
    expect_user_plugins_untouched

    # Install a declaratively managed plugin.
    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_user_plugins_untouched

    # Integration contract: OpenDeck's ownership patches consume this file.
    # Assert its exact representation here, rather than throughout the tests.
    printf '%s\n' '${managedId}' > "$root/expected-ownership"
    cmp -s "$root/expected-ownership" "$state"
    cp "$state" "$root/initial-ownership"

    # Repeated activation must preserve the effective installation, ownership
    # and user data. It need not preserve the symlink's inode.
    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # Dry-running removal must not alter an existing installation.
    DRY_RUN=1 bash "$root/removed.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # Upgrade and roll back the declared plugin without altering ownership.
    bash "$root/upgraded.sh"
    expect_link "$managed" "${new}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # Missing plugin sources must fail preflight without changing the
    # existing installation, ownership state or unrelated user plugins.
    expect_failure "$root/invalid.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # An unrelated plugin already installed by the user must not be overwritten,
    # even when another plugin in the requested activation is valid.
    mkdir -p "$otherTarget"
    printf '%s\n' 'do not overwrite' > "$otherTarget/settings.json"

    expect_failure "$root/conflicting.sh"
    expect_link "$managed" "${old}/${managedId}"
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # Removing a declaration removes its managed symlink but preserves
    # ordinary user-installed plugins.
    bash "$root/removed.sh"
    [[ ! -e "$managed" && ! -L "$managed" ]]
    [[ -f "$state" && ! -s "$state" ]]
    expect_user_plugins_untouched

    # An ordinary plugin with a colliding ID must still prevent installation.
    expect_failure "$root/conflicting.sh"
    [[ -f "$state" && ! -s "$state" ]]
    [[ ! -e "$managed" && ! -L "$managed" ]]
    expect_user_plugins_untouched

    # If a user replaces a managed symlink with an ordinary directory,
    # Home Manager must neither reclaim nor delete that directory.
    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"

    rm "$managed"
    mkdir -p "$managed"
    printf '%s\n' 'keep replacement' > "$managed/settings.json"

    # Even though ownership state still mentions this ID, the filesystem
    # no longer identifies it as Home Manager-managed.
    expect_failure "$root/initial.sh"
    [[ "$(cat "$managed/settings.json")" == 'keep replacement' ]]
    expect_ownership_unchanged
    expect_user_plugins_untouched

    # Removing the declaration must leave the replacement intact.
    bash "$root/removed.sh"
    [[ "$(cat "$managed/settings.json")" == 'keep replacement' ]]
    [[ -f "$state" && ! -s "$state" ]]
    expect_user_plugins_untouched

    touch "$out"
  ''
