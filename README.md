# OpenDeck for NixOS

<div align="center">

[Installation](#installation) | [Usage](#usage) | [Included plugin derivations](#plugin-listing)

</div>

Nix-OpenDeck lets you install [OpenDeck](https://github.com/nekename/OpenDeck) and its plugins
  declaratively through Nix, with the plugins able to remain immutable in the Nix store.

This is useful on NixOS because many OpenDeck plugins expect a conventional system
  environment and so don’t work correctly when installed through OpenDeck’s GUI.

It's still in early development, and is
 also my first attempt at derivations. I made it for myself, so I make no promises to maintain this
 long-term, but in the spirit of Nix, here ya go.

> [!IMPORTANT]  
> If you encounter bugs with the packages produced by this repo, it might not be
> the fault of the upstream repos, but a problem with nix-opendeck’s derivation, or OpenDeck’s handling of them.
> Be certain before contacting the upstream devs!

## Overview
nix-opendeck provides:
- A Nix-packaged build of OpenDeck patched  to support NixOS and plugins stored in the Nix store.
- Declarative packaging of OpenDeck/OpenActions plugins.
- A Home Manager module for declaratively installing plugins.
- A NixOS module for configuring OpenDeck and its required udev rules.
- Protection against OpenDeck overwriting Home Manager-managed plugins.
- Optional bundling of plugins directly into the OpenDeck package.

## Scope
### Core
This flake includes a patched version of OpenDeck to support plugins symlinked from the Nix store,
  as well as protect against collisions between plugins managed through the GUI and those managed by
  the [Home Manager module](#home-manager-module).

It emits three packages for OpenDeck:
- `opendeck-core`, which is the baseline OpenDeck with the patches applied.
- `opendeck`, which contains the bundled StarterPack plugin the upstream releases are built with.
  - `default` is an alias of `opendeck`.
- `opendeck-with-plugins`, a convenience package which bundles all plugins defined in this repo
    that do not declare [required runtime commands](#required-runtime-commands).

More information on the difference between a bundled plugin and a regular plugin [can be found here](#bundled-plugins).

By default, the [NixOS module](#nixos-module) and [Home Manager module](#home-manager-module)
use the `opendeck` package.

### Plugins
Plugins installed via the OpenDeck UI are often prone to failure due to incompatibilities with
  Nix’s non-traditional environment.

Because of that, and to allow for declarative configuration, this flake also contains derivations which
  patch and package plugins and their dependencies so that they can work properly in a Nix environment.

[Check here for a list of plugins included in this flake](#plugin-listing).

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
> When using both the NixOS and Home Manager modules, make sure that they're using the same [package](#changing-the-package-used-by-the-nixos-or-home-manager-modules)!

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

The Home Manager module lets you declare plugins you’d like to use, and installs them to OpenDeck by
  making them available in OpenDeck's XDG plugin directory via links from the Nix store.

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
> You will also receive a warning from the Home Manager module if you attempt to overwrite a plugin
> with Home Manager which is already installed via the graphical interface.

### Usage without the NixOS or Home Manager modules

#### Udev Rules
If you're not using the NixOS module, you'll need to install the required udev rules in order for
  OpenDeck to detect your Stream Deck.

They are available in the upstream repository [here](https://raw.githubusercontent.com/OpenActionAPI/rust-elgato-streamdeck/main/40-streamdeck.rules).

#### Using the plugin derivations

OpenDeck looks for plugins at `$XDG_CONFIG/opendeck/plugins/`. You could symlink the plugins from the
  nix store directly into there, and the patched `opendeck` should be able to use them.

Alternatively, you could override the `opendeck` or `opendeck-core` packages to [bundle](#bundled-plugins)
  plugins into them.

You could also use the `opendeck-with-plugins` package, which comes with every plugin in the 
  [Plugin Listing](#plugin-listing) which does not declare required commands, though this is
  not recommended, as bundling many plugins increases the size of the resulting package and
  requires OpenDeck to be rebuilt whenever the bundle changes.

### Overlay
The flake emits an overlay to add the flake's packages to your local nixpkgs at 
  `inputs.opendeck.overlays.default`.

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

When the program starts up, OpenDeck will check its bundled plugins against the plugins installed by the user.
  If any are missing or outdated compared to the plugin in its bundle, it will copy the bundled version into 
  the user's `plugins` directory.

Modifying or updating bundled plugins necessitates recompiling the entire binary. They're only really useful
  if you want to use the nix-built plugins, but can't use nix-opendeck's Home Manager module and don't want
  to symlink them from the store.

Upstream OpenDeck comes with the "Starter Pack" plugin bundled by default, so the `opendeck` package does
  as well.

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

By default, this is set to `opendeck`, however you can change it if you want to use a different version of
  the package, for example `opendeck-core`, in which case you will need to manually declare
  `opendeck-plugin-starterpack` as a plugin in your Home Manager configuration.

### Required runtime commands
Some plugins invoke external commands at runtime. When nix-opendeck does not provide such a command as
  part of the plugin package, it is listed as a runtime command and must be available in your `PATH`.

Required runtime commands are checked by the Home Manager module when the plugin is enabled.

Plugins may also integrate with external services, such as PipeWire, D-Bus services, or another running
  application. These integrations are documented in the plugin listing, but are not checked or provided
  by nix-opendeck.

## Plugin Listing
Below is a list of the plugins where a derivation is included in this repo. You can check their upstream
  sources for more information.

| Upstream plugin | Package name | Required runtime commands | External integrations |
| --- | --- | --- | --- |
| [Starterpack](https://github.com/nekename/OpenDeck/tree/main/plugins/com.amansprojects.starterpack.sdPlugin) | `opendeck-plugin-starterpack` | - | - |
| [Analog Clock](https://github.com/elgatosf/streamdeck-analogclock/) | `opendeck-plugin-analogclock` | - | - |
| [Linux App Launcher](https://github.com/OpenActionPlugins/desktopentry) | `opendeck-plugin-desktopentry` | - | - |
| [OpenAction Discord Plugin](https://github.com/OpenActionPlugins/discord) | `opendeck-plugin-oadiscord` | - | Discord IPC |
| [Home Assistant](https://github.com/cgiesche/streamdeck-homeassistant) | `opendeck-plugin-homeassistant` | - | - |
| [MPRIS Media Controls](https://github.com/OpenActionPlugins/mpris) | `opendeck-plugin-mpris` | - | MPRIS-compatible player |
| [Multi OBS Controller](https://github.com/theca11/multi-obs-controller) |  `opendeck-plugin-multi-obs-controller` | - | OBS Studio |
| [On Air Clock](https://github.com/wortkrieg/streamdeck-onairclock) | `opendeck-plugin-onairclock` | - | - |
| [PipeWire Audio Control](https://github.com/sjourdois/opendeck-pipewire) | `opendeck-plugin-pipewire` | - | PipeWire |
| [Redline Monitor](https://github.com/kahikara/opendeck-redline-monitor) | `opendeck-plugin-redline-monitor` | - | See upstream |
| [TikClock](https://github.com/GDWhisper/opendeck-tikclock) | `opendeck-plugin-tikclock` | - | - |
| [Tomato Timer](https://github.com/gallowaylabs/streamdeck-tomato-timer) | `opendeck-plugin-tomatotimer` | - | - |
| [OpenDeck Weather](https://github.com/jfms7s/opendeck-weather) | `opendeck-plugin-jfms7s-weather` | - | - |
| [XIVDeck](https://github.com/KazWolfe/XIVDeck) | `opendeck-plugin-xivdeck` | - | FFXIV / Dalamud |
