# Return OpenDeck and plugin CI targets for one Nix system.
# The flake's platform-filtered catalogue is the source of truth.
{ flake, system }:
let
  lib = flake.inputs.nixpkgs.lib;

  runner = {
    x86_64-linux = "ubuntu-24.04";
    aarch64-linux = "ubuntu-24.04-arm";
    aarch64-darwin = "macos-15";
  }.${system};

  plugins = flake.legacyPackages.${system}.opendeck-plugins;
  names = attrs: builtins.filter (n: n != "recurseForDerivations") (builtins.attrNames attrs);

  redistributable = drv:
    let
      licenses = lib.toList (drv.meta.license or [ ]);
    in
    licenses != [ ] && lib.all (license: license.redistributable or false) licenses;

  target = kind: attr: label: drv: {
    inherit system runner kind attr label;
    storePath = drv.outPath;
    redistributable = redistributable drv;
    updatable = (drv.updateScript or null) != null;
  };
in
{
  opendeck = target "opendeck" "packages.${system}.opendeck" "opendeck" flake.packages.${system}.opendeck;

  plugins = lib.concatMap (owner:
    map (name:
      target "plugin"
        "legacyPackages.${system}.opendeck-plugins.${owner}.${name}"
        "${owner}/${name}"
        plugins.${owner}.${name}
    ) (names plugins.${owner})
  ) (names plugins);
}
