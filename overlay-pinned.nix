_final: prev:

(import ./default.nix {
  system = prev.stdenv.hostPlatform.system;
  usePinnedNixpkgs = true;
}).overlayAttrs
