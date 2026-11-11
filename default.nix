{
  system ? builtins.currentSystem,
  pkgs ? null,
  usePinnedNixpkgs ? false,
}:

let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);

  fetchLockedInput =
    name:
    let
      nodeName = lock.nodes.root.inputs.${name};
      locked = lock.nodes.${nodeName}.locked;
    in
    assert locked.type == "github";
    fetchTarball {
      url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
      sha256 = locked.narHash;
    };

  packageSet =
    if pkgs != null then
      pkgs
    else if usePinnedNixpkgs then
      import (fetchLockedInput "nixpkgs") { inherit system; }
    else
      import <nixpkgs> { inherit system; };

  outputs = import ./src/packages {
    inputs = {
      deno-nixpkgs = fetchLockedInput "deno-nixpkgs";
    };

    pkgs = packageSet;
  };

in
outputs.packages
// outputs.legacyPackages
// {
  overlayAttrs = outputs.overlayAttrs;

  homeManagerModules.default = import ./src/modules/home-manager {
    defaultPackage = outputs.packages.opendeck;
  };
}
