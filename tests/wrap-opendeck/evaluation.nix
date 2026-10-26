{
  pkgs,
  fixtures,
}:

let
  inherit (pkgs) lib;

  inherit (fixtures)
    core
    plugin
    pluginId
    wrapped
    wrapOpenDeck
    ;

  evaluates = drv: (builtins.tryEval drv.drvPath).success;

  duplicateIds = wrapOpenDeck {
    package = core;
    plugins = [
      plugin
      plugin
    ];
  };

  alreadyBundled = wrapOpenDeck {
    package = core // {
      bundledPluginIds = [ "existing.sdPlugin" ];
    };
  };

in

assert lib.assertMsg (evaluates wrapped) "Valid OpenDeck wrapper should evaluate";

assert lib.assertMsg (!evaluates duplicateIds) "Duplicate plugin IDs should be rejected";

assert lib.assertMsg (
  !evaluates alreadyBundled
) "Already-bundled OpenDeck packages should be rejected";

assert lib.assertMsg (
  wrapped.bundledPluginIds == [ pluginId ]
) "Wrapper should expose its bundled plugin IDs";

assert lib.assertMsg (
  wrapped.version == core.version
) "Wrapper should preserve the core package version";

pkgs.runCommand "opendeck-wrap-evaluation" { } ''
  touch "$out"
''
