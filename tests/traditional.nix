{ pkgs, lib }:

let
  traditional = import ../default.nix {
    inherit pkgs;
  };

  overlaid = pkgs.appendOverlays [
    (import ../overlay.nix)
  ];

  pinned = import ../default.nix {
    system = pkgs.stdenv.hostPlatform.system;
    usePinnedNixpkgs = true;
  };

  pinnedOverlaid = pkgs.appendOverlays [
    (import ../overlay-pinned.nix)
  ];
in

assert lib.assertMsg (
  traditional.opendeck.drvPath == overlaid.opendeck.drvPath
) "Traditional overlay should produce the same OpenDeck derivation as default.nix";

assert lib.assertMsg (builtins.isString overlaid.opendeck-plugins.nekename.starterpack.drvPath)
  "Traditional overlay should expose plugin derivations";

assert lib.assertMsg (
  pinned.opendeck.drvPath == pinnedOverlaid.opendeck.drvPath
) "Pinned overlay should match the pinned standalone package";

assert lib.assertMsg
  (builtins.isString pinnedOverlaid.opendeck-plugins.nekename.starterpack.drvPath)
  "Pinned overlay should expose plugin derivations";

pkgs.runCommand "opendeck-traditional-evaluation" { } ''
  touch "$out"
''
