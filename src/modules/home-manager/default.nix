{ defaultPackage }:
{ ... }:
{
  imports = [
    (import ./options.nix { inherit defaultPackage; })
    ./settings.nix
    ./activation.nix
  ];
}
