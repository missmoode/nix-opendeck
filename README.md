# OpenDeck for NixOS

Nix-OpenDeck lets you install [OpenDeck](https://github.com/nekename/OpenDeck) and its plugins declaratively through Nix, 
with the plugins able to remain immutable in the Nix store.

This is useful on NixOS because many OpenDeck plugins expect a conventional system environment and so don’t work correctly
when installed through OpenDeck’s GUI.

It's still in early development, and is
also my first attempt at derivations. I made it for myself, so I make no promises to maintain this
long-term, but in the spirit of Nix, here ya go.

> [!IMPORTANT]  
> If you encounter bugs with the packages produced by this repo, it might not be
> the fault of the upstream repos, but a problem with this derivation.
> Be certain before contacting the upstream devs!

## Scope
### Core
This flake includes a patched version of OpenDeck to support plugins symlinked from the nix store,
as well as protect against collisions between plugins managed through the GUI and those managed by
the [Home Manager Module](#home-manager-module).

It emits two packages for OpenDeck:
- `opendeck-core`, which is the baseline opendeck with the patches applied.
- `opendeck`, which contains the bundled StarterPack plugin the upstream releases are built with.
  - `default` is an alias of `opendeck`.

By default, the [NixOS Module](#nixos-module) and [Home Manager Module](#home-manager-module)
use the `opendeck` package.

More information on the difference between a bundled plugin and a regular plugin [can be found here](#bundled-plugins).

### Plugins
Plugins installed via the OpenDeck UI are often prone to failure due to being unpatched for NixOS’s environment.

Because of that, and to allow for declarative configuration, this flake also contains derivations which
patch and package plugins and their dependencies. [Check here for a list of plugins included in this flake](#plugin-listing).

Alternatively, you could try using [nix-ld](https://github.com/nix-community/nix-ld) to better resemble
the environment the unpatched plugins expect.

## Installation
### Flakes

Import the flake as normal:
```nix
opendeck = {
  url = "github:missmoode/nix-opendeck";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

## Usage
> [!IMPORTANT]  
> When using both the NixOS and Home Manager modules, make sure that they're using the same [package](#changing-the-package-used-in-the-modules)!

### NixOS Module

Use of this module is required to automatically set up udev rules.

If you're not using NixOS, you must set them up yourself. See the section on [usage without the modules](#usage-without-the-nixos-or-home-manager-modules).

```nix
{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    inputs.opendeck.nixosModules.default
  ];

  config = {
    # ...
    programs.opendeck.enable = true;
    # ...
  };
}
```

### Home Manager Module

The Home Manager module lets you declare plugins you’d like to use, and installs them to OpenDeck by making them available in OpenDeck's
XDG plugin directory via links from the Nix store.

```nix
{
  inputs,
  pkgs,
  ...
}:
let
  opendeckpkgs = inputs.opendeck.${pkgs.stdenv.hostPlatform.system}.packages;
in
{
  imports = [
    inputs.opendeck.homeManagerModules.default
  ];

  config = {
    # ...
    programs.opendeck = {
      enable = true;
      plugins = with opendeckpkgs; [
        opendeck-plugin-desktopentry
        opendeck-plugin-pipewire
        # ...
      ];
    };
    # ...
  };
}
```

> [!IMPORTANT]  
> nix-opendeck patches OpenDeck to prevent updates or removal of plugins installed via Home Manager.
> You will also recieve a warning from the Home Manager module if you attempt to overwrite a plugin
> with Home Manager which is already installed via the graphical interface.

### Usage without the NixOS or Home Manager modules

#### UDev Rules
If you're not using the NixOS module, you'll need to install the required UDev rules in
order for OpenDeck to detect your Stream Deck.

They are available in the upstream repository [here](https://raw.githubusercontent.com/OpenActionAPI/rust-elgato-streamdeck/main/40-streamdeck.rules).

#### Using the plugin derivations

OpenDeck looks for plugins at `$XDG_CONFIG/opendeck/plugins/`. You could symlink the plugins from the nix store directly into there, and the patched `opendeck` should be able to use them.

Alternatvely, you could override the `opendeck` or `opendeck-core` packages to [bundle](#bundled-plugins) plugins into them.

### Overlay
The flake emits an overlay to add the flake's packages to your local nixpkgs at `inputs.opendeck.overlays.default`.

Once you've applied it, your configuration can be simplified to just use your existing `pkgs` argument:
```nix
{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    inputs.opendeck.homeManagerModules.default
  ];

  # ...

  programs.opendeck = {
    enable = true;
    plugins = with pkgs; [
      opendeck-plugin-desktopentry
      opendeck-plugin-pipewire
      # ...
    ];
  };

  # ...
}
```

## Information
### Bundled Plugins

OpenDeck can be built with plugins bundled directly into its binary as mandatory defaults.

When the program starts up, OpenDeck will check its bundled plugins against the plugins installed by the user. If any are missing or outdated compared to the plugin in its bundle, it will copy the bundled version into the user's `plugins` directory.

Modifying or updating bundled plugins necessitates recompiling the entire binary. They're only really useful if you want to use the nix-built plugins, but can't use nix-opendeck's Home Manager module and don't want to symlink them from the store.

Upstream OpenDeck comes with the "Starter Pack" plugin bundled by default, so the `opendeck` package does as well.

### Overriding the bundled plugins
You can bundle plugins yourself by overriding the `opendeck` or `opendeck-core` packages
and using the `bundledPlugins` argument:
```nix
environment.systemPackages = [
  # Using opendeck-core, which has an empty bundle list by default
  (pkgs.opendeck-core.override {
    bundledPlugins = with pkgs; [
      # This plugin is only in the bundledPlugins of pkgs.opendeck, so we'll need to re-add it
      # or override pkgs.opendeck instead.
      opendeck-plugin-starterpack

      # Other bundled plugins...
      opendeck-plugin-pipewire
      opendeck-plugin-mpris
      # ... etc
    ];
  });
];
```

### Changing the package used by the NixOS or Home Manager modules
The package used by the NixOS and Home Manager modules can be changed by modifying `programs.opendeck.package`.

By default, this is set to `opendeck`, however you can change it to `opendeck-core`, in which case you will
need to manually declare `opendeck-plugin-starterpack` as a plugin in your Home Manager configuration.

### Changing the zoom of the OpenDeck UI interface
This derivation also adds a lever for a convenience feature to change the scale of the OpenDeck GUI.
To use it, modify the `webviewZoom` argument:
```nix
opendeck-local = (
  _final: prev: {
    opendeck = prev.opendeck.override {
      webviewZoom = 0.8; # By default, it's at 1.
    };
  }
);
```

## Plugin Listing
Below is a list of the plugins where a derivation is included in this repo. You can check their upstream sources for more information.

| Upstream Plugin | Package name |
| --- | --- |
| [Starterpack](https://github.com/nekename/OpenDeck/tree/main/plugins/com.amansprojects.starterpack.sdPlugin) | `opendeck-plugin-starterpack` |
| [Linux App Launcher](https://github.com/OpenActionPlugins/desktopentry) | `opendeck-plugin-desktopentry` |
| [OpenAction Discord Plugin](https://github.com/OpenActionPlugins/discord) | `opendeck-plugin-oadiscord` |
| [HomeAssistant](https://github.com/cgiesche/streamdeck-homeassistant) | `opendeck-plugin-homeassistant` |
| [MPRIS Media Controls](https://github.com/OpenActionPlugins/mpris) | `opendeck-plugin-mpris` |
| [Pipewire Audio Control](https://github.com/sjourdois/opendeck-pipewire) | `opendeck-plugin-pipewire` |
| [TikClock](https://github.com/GDWhisper/opendeck-tikclock) | `opendeck-plugin-tikclock` |
| [XIVDeck](https://github.com/KazWolfe/XIVDeck) | `opendeck-plugin-xivdeck` |
