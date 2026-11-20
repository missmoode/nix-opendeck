{
  pkgs,
  support,
}:

let
  inherit (support)
    mkPlugin
    mkActivation
    managedId
    otherId
    userId
    ;
  old = mkPlugin managedId "old";
  new = mkPlugin managedId "new";
  other = mkPlugin otherId "other";
  missing = pkgs.runCommand "opendeck-hm-test-plugin-missing" { passthru.pluginId = managedId; } ''
    mkdir -p "$out"
  '';

  script =
    plugins:
    mkActivation {
      inherit plugins;
      reloadOnPluginChanges = false;
    };
  initial = script [ old ];
  upgraded = script [ new ];
  removed = script [ ];
  conflicting = script [
    new
    other
  ];
  invalid = script [ missing ];

  check =
    plugins:
    support.mkCheck {
      inherit plugins;
      reloadOnPluginChanges = false;
    };
  initialCheck = check [ old ];
  conflictingCheck = check [
    new
    other
  ];

  # Conflicts must be rejected before Home Manager creates the generation.
  order = support.activationOrder { plugins = [ old ]; };
  position = name: pkgs.lib.lists.findFirstIndex (entry: entry == name) null order;
in
assert pkgs.lib.assertMsg (
  position "checkOpenDeck" < position "writeBoundary"
  && position "writeBoundary" < position "opendeck"
) "OpenDeck activation order is wrong: ${builtins.toJSON order}";
pkgs.runCommand "opendeck-home-manager-activation-plugins" { inherit (support) nativeBuildInputs; }
  ''
    ${support.setup}

    managed="$pluginDir/${managedId}"
    otherTarget="$pluginDir/${otherId}"
    userTarget="$pluginDir/${userId}"

    render ${initialCheck} "$root/initial-check.sh"
    render ${conflictingCheck} "$root/conflicting-check.sh"

    # The preflight is read-only: it creates no configuration directory.
    bash "$root/initial-check.sh"
    DRY_RUN=1 bash "$root/initial-check.sh"
    [[ ! -e "$configDir" ]]

    render ${initial} "$root/initial.sh"
    render ${upgraded} "$root/upgraded.sh"
    render ${removed} "$root/removed.sh"
    render ${conflicting} "$root/conflicting.sh"
    render ${invalid} "$root/invalid.sh"

    mkdir -p "$userTarget"
    printf '%s\n' 'user data' > "$userTarget/settings.json"

    DRY_RUN=1 bash "$root/initial.sh"
    [[ ! -e "$managed" && ! -L "$managed" && ! -e "$state" ]]

    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"
    printf '%s\n' '${managedId}' > "$root/expected-ownership"
    cmp -s "$root/expected-ownership" "$state"
    cp "$state" "$root/initial-ownership"
    [[ "$(cat "$userTarget/settings.json")" == 'user data' ]]

    # Idempotence includes the ownership file, not just the symlink target.
    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"
    cmp -s "$root/initial-ownership" "$state"

    DRY_RUN=1 bash "$root/removed.sh"
    expect_link "$managed" "${old}/${managedId}"

    bash "$root/upgraded.sh"
    expect_link "$managed" "${new}/${managedId}"
    cmp -s "$root/initial-ownership" "$state"
    bash "$root/initial.sh"
    expect_link "$managed" "${old}/${managedId}"

    # A missing source and a conflicting ordinary installation both fail
    # before changing any existing plugin or ownership state.
    expect_failure "$root/invalid.sh"
    expect_link "$managed" "${old}/${managedId}"
    cmp -s "$root/initial-ownership" "$state"

    mkdir -p "$otherTarget"
    printf '%s\n' 'do not overwrite' > "$otherTarget/settings.json"
    expect_failure "$root/conflicting.sh"
    expect_link "$managed" "${old}/${managedId}"
    cmp -s "$root/initial-ownership" "$state"

    # The pre-writeBoundary check rejects the same conflict, including in a
    # dry run, without touching anything in the configuration directory.
    snapshot() { (cd "$configDir" && find . -printf '%p %y %l %s\n' | sort); }
    snapshot > "$root/before-check"
    expect_failure "$root/conflicting-check.sh"
    DRY_RUN=1 expect_failure "$root/conflicting-check.sh"
    snapshot > "$root/after-check"
    cmp -s "$root/before-check" "$root/after-check"
    [[ "$(cat "$otherTarget/settings.json")" == 'do not overwrite' ]]

    bash "$root/removed.sh"
    [[ ! -e "$managed" && ! -L "$managed" ]]
    [[ -f "$state" && ! -s "$state" ]]
    [[ "$(cat "$userTarget/settings.json")" == 'user data' ]]
    [[ "$(cat "$otherTarget/settings.json")" == 'do not overwrite' ]]

    # Users may replace the managed link with an ordinary plugin directory.
    bash "$root/initial.sh"
    rm "$managed"
    mkdir -p "$managed"
    printf '%s\n' 'keep replacement' > "$managed/settings.json"
    expect_failure "$root/initial.sh"
    [[ "$(cat "$managed/settings.json")" == 'keep replacement' ]]
    cmp -s "$root/initial-ownership" "$state"
    bash "$root/removed.sh"
    [[ "$(cat "$managed/settings.json")" == 'keep replacement' ]]
    [[ ! -s "$state" ]]

    expect_commands ""
    touch "$out"
  ''
