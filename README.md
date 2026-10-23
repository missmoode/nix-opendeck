# OpenDeck on Nix

> [!WARNING]
> Breaking changes may still happen for a little while. This README will remain up-to-date.

> [!NOTE]
> I’m pretty sure that this is properly reproducible, but I’ve not verified this yet.
> The main issues I could find were Deno’s lack of a viable helper, which I think
> I’ve solved by pinning it, and SvelteKit, where I *think* replacing the version 
> string allowed it to act deterministically.

<div align="center">

[Installation](#installation) | [Usage](#usage) | [Plugin Listing](#plugin-listing)

</div>

nix-opendeck lets you install [OpenDeck](https://github.com/nekename/OpenDeck) and its
plugins declaratively through Nix, while keeping the plugins immutable in the Nix store.

This is useful on NixOS, where plugins installed through OpenDeck's GUI may fail because
their binaries expect a conventional system. On other platforms, nix-opendeck still
provides declarative plugin management and reproducible packaging.

This is my first attempt at packaging software for Nix, made out of a personal need
for my Stream Deck to just work on NixOS. I make no promises to maintain this
long-term, but in the spirit of Nix, I'm making it public and doing what I can
to make it useful for everyone.

> [!IMPORTANT]  
> If you encounter bugs with the packages produced by this repo, it might not be
> the fault of the upstream projects, but a problem with nix-opendeck’s derivation,
> or OpenDeck’s handling of them.
> 
> Be certain before contacting the upstream devs!

## Overview
nix-opendeck provides:
- A Nix-packaged build of OpenDeck patched to support immutable plugins symlinked from
the Nix store.
- Declarative packaging of OpenDeck/OpenActions plugins.
- A Home Manager module to declaratively manage plugins, and optionally install OpenDeck.
- Udev rules packages for OpenDeck and plugins requiring device access.
- Protection against OpenDeck modifying externally managed plugins.
- Optional bundling of plugins (and Udev rules) directly into the OpenDeck package.

## Scope
### Philosophy
nix-opendeck aims to make OpenDeck and its plugins work well when installed through Nix,
particularly with immutable store paths and declarative configuration.

While the goal is to stay close to upstream OpenDeck, this repository includes downstream
patches where necessary to address compatibility issues or make the experience of using
OpenDeck with Nix smoother. Some changes fix functionality that would otherwise break,
while others improve integration with tools like Home Manager.

I'm considering these changes on a case-by-case basis, with a preference for using the
existing upstream functionality where I can, and using small, maintainable patches where
I feel it's warranted.

### Core
This flake includes a patched version of OpenDeck to support plugins symlinked from the
Nix store, as well as protection against collisions between plugins managed through the
GUI and plugins managed externally, for example by the [Home Manager module](#home-manager-module).

It emits three packages for OpenDeck:
- `opendeck-core`, which is the baseline OpenDeck with the patches applied.
- `opendeck`, which contains the bundled StarterPack plugin the upstream releases are built with.
  - `default` is an alias of `opendeck`.
- `opendeck-with-plugins`, a convenience package which bundles all plugins available on
the selected
platform that do not declare [required runtime commands](#required-runtime-commands) or additional udev rules.

More information on the difference between a bundled plugin and a regular plugin [can be found here](#bundled-plugins).

By default, the [Home Manager module](#home-manager-module) installs the `opendeck` package.

### Plugins
This flake also provides derivations for some OpenDeck plugins, packaging their dependencies and
applying compatibility patches where necessary.

These packages can be managed declaratively rather than through OpenDeck's graphical plugin store.

[Check here for a list of plugins included in this flake](#plugin-listing).

On NixOS, you could alternatively try using [nix-ld](https://github.com/nix-community/nix-ld) to run unpatched plugins that expect conventional Linux library and dynamic linker paths.

## Installation
### Supported Platforms

nix-opendeck currently targets Linux (`x86_64-linux` and `aarch64-linux`) and macOS on Apple
Silicon (`aarch64-darwin`). It's tested working on NixOS, and should also work on nix-darwin or
standalone Nix installations on supported systems.

> [!WARNING]
> I've only tested it on NixOS on x86_64. While everything seems to compile for the others,
> I don't have the hardware to check. If you're on Linux aarch64 or Apple Silicon and trying this
> out, you're welcome to open an issue and let me know if it works!

The Home Manager module supports both Linux and macOS.

On NixOS, device permissions are configured through the standard `services.udev.packages` option, using the udev rules packages provided by this flake.

### Standalone OpenDeck
If you just want the package, and don't care about the modules or flake stuff:

```bash
nix profile add github:missmoode/nix-opendeck#opendeck
```

This won't automatically configure device permissions: you'll need to [do that yourself](#device-access-on-other-linux-distributions).

### Flakes

Import the flake as normal:
```nix
opendeck = {
  url = "github:missmoode/nix-opendeck";

  # Optionally, bring your own nixpkgs.
  # This may prevent binary cache hits.
  # 
  # inputs.nixpkgs.follows = "nixpkgs";
};
```

### Binary Cache

A binary cache is available on [Cachix](https://app.cachix.org/cache/nix-opendeck) for
`opendeck` and redistributable plugins on the supported platforms, allowing you
to download pre-built packages instead of compiling them locally.

On NixOS or nix-darwin, add the following to your system configuration:

```nix
{
  nix.settings = {
    extra-substituters = [
      "https://nix-opendeck.cachix.org"
    ];

    extra-trusted-public-keys = [
      "nix-opendeck.cachix.org-1:twvVjvv6Xm9H/m9sD2YQfIDoeUZLWEX5CpokN2An9L8="
    ];
  };
}
```

On other systems with Nix installed, add the following to your Nix configuration (usually at
`/etc/nix/nix.conf` for a multi-user installation):

```ini
extra-substituters = https://nix-opendeck.cachix.org
extra-trusted-public-keys = nix-opendeck.cachix.org-1:twvVjvv6Xm9H/m9sD2YQfIDoeUZLWEX5CpokN2An9L8=
```

> [!NOTE]
> To benefit from the cache on your first installation, activate the new Nix settings before
> installing OpenDeck. Otherwise, OpenDeck may be compiled locally because the new cache 
> configuration hasn't yet been activated.
>
> Cache hits also depend on matching Nix derivations. Overriding this flake's `nixpkgs` input with `inputs.nixpkgs.follows` may result in cache misses.

## Usage

### Device Access on NixOS

OpenDeck requires udev rules to access supported USB devices. The OpenDeck packages expose
a `.udev` attribute containing the core Stream Deck rules, along with any additional rules
provided by bundled plugins.

Install these rules through NixOS's standard `services.udev.packages` option:

```nix
{
  inputs,
  pkgs,
  ...
}:
let
  opendeck = inputs.opendeck.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
in
{
  services.udev.packages = [
    opendeck.udev
    # To include the rules from a non-bundled hardware plugin:
    # opendeck-plugins."4ndv".akp03.udev
  ];

  # This only installs the udev rules, not OpenDeck itself.
  # If you're not using the Home Manager module, you can install it system-wide:
  #
  # environment.systemPackages = [ opendeck ];
}
```

Device support plugins installed separately, including through Home Manager, may expose
their own `.udev` packages. If a plugin requires additional udev rules, add its `.udev`
attribute to `services.udev.packages` as well.

### Device access on other Linux distributions

On Linux distributions other than NixOS, you'll need to install the required udev rules manually to allow OpenDeck to access your device.

See the relevant step of OpenDeck's [Linux installation instructions](https://github.com/nekename/OpenDeck#linux).

### Home Manager Module

The Home Manager module lets you declare plugins you’d like to use, and installs them to OpenDeck by
making them available in OpenDeck's plugin directory via symlinks from the Nix store.

It can be used with standalone Home Manager, or as part of a NixOS or nix-darwin configuration.

```nix
{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  
  opendeckpkgs = inputs.opendeck.packages.${system};
  opendeck-plugins = inputs.opendeck.legacyPackages.${system}.opendeck-plugins;
in
{
  imports = [
    inputs.opendeck.homeManagerModules.default
  ];

  config = {
    # ...
    programs.opendeck = {
      enable = true;

      # You can change this option to use a different
      # OpenDeck package from the default.
      # package = opendeckpkgs.opendeck-core;
      
      # You can also avoid having the module install the
      # package for you, if you want to do it yourself.
      # installPackage = false;

      plugins = with opendeck-plugins; [
        data-enabler.web-requests
        gallowaylabs.tomato-timer
        # ...
      ];
    };
    # ...
  };
}
```

If `programs.opendeck.installPackage` is `false`, `programs.opendeck.package` should
still match the OpenDeck package you installed elsewhere. The module uses it to check
which plugins are already bundled and prevent accidental double-declarations, as well
as to notify a running OpenDeck instance of plugin changes.

> [!IMPORTANT]  
> Plugins managed by the Home Manager module are marked as externally managed. The 
> OpenDeck package includes patches that prevent its plugin manager from updating
> or removing externally managed plugins.
> 
> Plugins installed through the GUI are unaffected. The Home Manager module will
> refuse to overwrite plugins unless they're marked as externally managed.

When Home Manager adds, removes, or updates a plugin, it notifies the running
OpenDeck instance to load, unload, or reload that plugin without restarting
OpenDeck. Only plugins whose installed paths are changed are affected.

If OpenDeck isn't running (or the notification fails), the changes will
take effect when OpenDeck next starts as normal.

#### Using a different package
The package used by the Home Manager module can be changed by modifying `programs.opendeck.package`.

By default, this is set to `opendeck`. However, you can change it if you want to use a different version of
the package, for example `opendeck-core`, in which case you will need to manually declare
`opendeck-plugins.nekename.starterpack` as a plugin in your Home Manager configuration.

### Usage without the Home Manager module

#### Using the plugin derivations

OpenDeck looks for plugins within its config directory:
- Linux: `$XDG_CONFIG_HOME/opendeck/plugins/`
- macOS: `~/Library/Application Support/opendeck/plugins/`

You could symlink the plugins from the Nix store (or elsewhere) directly into there, and
the patched `opendeck` should be able to use them. However, without the Home Manager
module they will not be protected from modification through the GUI.

If you manage plugin symlinks yourself, you can notify a running OpenDeck
instance of a change without restarting it:

```bash
opendeck --sync-plugin com.example.plugin.sdPlugin
```

The command accepts a single plugin ID, rather than a filesystem path.
It loads or reloads the plugin if its directory exists, or unloads it if
the directory has been removed. It does not start OpenDeck if it isn't
already running.

Alternatively, you could override the `opendeck` or `opendeck-core` packages to 
[bundle](#bundled-plugins) plugins into them.

You could also use the `opendeck-with-plugins` package, which bundles every plugin in the 
[Plugin Listing](#plugin-listing) available on the selected platform which does not
declare required commands or udev rules. This is not recommended, as any changes to
OpenDeck or its plugins will require recompiling the whole thing.

### Overlay

Overlays are optional. The Home Manager module and NixOS udev configuration work without
them, but an overlay lets you access OpenDeck, its plugins, and their udev rules through
your existing `pkgs` argument.

The flake provides two overlays which expose OpenDeck and its plugins through your existing `pkgs` argument:
- **`inputs.opendeck.overlays.pinned` (recommended):** Uses the same pinned
dependencies as nix-opendeck's CI builds, allowing packages to be substituted from
the [binary cache](#binary-cache) when available.
- **`inputs.opendeck.overlays.default`:** Builds packages against your own Nixpkgs,
allowing them to share dependencies with your system. This may result in cache
misses and local compilation.

> [!IMPORTANT]
> To benefit from the binary cache when using `overlays.pinned`, do not set
> `opendeck.inputs.nixpkgs.follows = "nixpkgs"` in your flake inputs. Doing
> so overrides nix-opendeck's locked Nixpkgs revision, potentially producing
> different derivations from those published by CI.
>
> If you prefer to use your system's Nixpkgs, `overlays.default` is recommended
> instead.

On NixOS or nix-darwin, add your chosen overlay to your system configuration:
```nix
{
  inputs,
  ...
}:
{
  nixpkgs.overlays = [
    inputs.opendeck.overlays.pinned
  ];
}
```

If you're just using Home Manager, you can configure an overlay through your own Nixpkgs instance.

Once applied, you can reference OpenDeck packages directly through `pkgs` in
your Home Manager configuration:
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

    # Use the OpenDeck package provided by the overlay.
    package = pkgs.opendeck;

    plugins = with pkgs.opendeck-plugins; [
      data-enabler.web-requests
      gallowaylabs.tomato-timer
      # ...
    ];
  };

  # ...
}
```

> [!NOTE]
> If Home Manager uses a separate Nixpkgs instance on systems integrated with NixOS or nix-darwin,
> the overlay must also be applied  to that instance. When `home-manager.useGlobalPkgs = true`,
> the system-level overlay is shared automatically.
> 
> The Home Manager module uses nix-opendeck's own `opendeck` package by default,
> independently of the chosen overlay.
> Setting `programs.opendeck.package = pkgs.opendeck` ensures that it uses the
> overlay-provided package.
>
> Custom package overrides may also produce different store paths and require local
> compilation.

## Information
### OpenDeck Compatibility Patches

nix-opendeck applies a small collection of downstream patches to OpenDeck to improve compatibility
with Nix installations.

These patches:
- Support plugins symlinked from the immutable Nix store, including their assets and
executable permissions.
- Prevent OpenDeck from modifying or removing plugins marked as externally managed.
- Allow external package managers to explicitly notify OpenDeck when individual plugins
are added, removed, or updated, without requiring a restart (matching the behaviour when
installed via the GUI).
- Preserve runtime paths provided by Nix wrappers for use in application-based profile switching.
- Modify OpenDeck's "start at launch" setting behaviour to preserve functionality between package upgrades.

The Nix build also includes minor changes to identify itself and direct users to the relevant
plugin compatibility documentation.

### Bundled Plugins

OpenDeck can be built with plugins bundled directly into its binary as mandatory defaults.

When the program starts up, OpenDeck will check its bundled plugins against the plugins installed by the user.
If any are missing or outdated compared to the plugin in its bundle, it will copy the bundled version into 
the user's `plugins` directory.

Modifying or updating bundled plugins necessitates recompiling the entire binary. Bundled plugins are mainly useful
if you want to use the Nix-built plugins, but can't use nix-opendeck's Home Manager module, and don't want
to symlink them from the store.

Upstream OpenDeck comes with the "Starter Pack" plugin bundled by default, so the `opendeck` package does
  as well.

### Overriding the bundled plugins
You can bundle plugins yourself by overriding the `opendeck` or `opendeck-core` packages
and using the `bundledPlugins` argument:

```nix
# Assuming an overlay has been applied:
pkgs.opendeck-core.override {
  bundledPlugins = with pkgs.opendeck-plugins; [
    # This plugin is only in the bundledPlugins of pkgs.opendeck, so we'll
    # need to re-add it or override pkgs.opendeck instead.
    nekename.starterpack

    # Other bundled plugins...
    data-enabler.web-requests
    gallowaylabs.tomato-timer
    # ... etc
  ];
}
```

If a bundled plugin provides udev rules, they are automatically included in the resulting
OpenDeck package's `.udev` attribute. On NixOS, these rules still need to be explicitly
installed through `services.udev.packages`.

Plugins installed separately through Home Manager do not contribute rules to the OpenDeck
package's `.udev` attribute.

The resulting package can then be installed through a mechanism of your choosing.

### Required runtime commands
Some plugins invoke external commands at runtime. When nix-opendeck does not provide such a command as
part of the plugin package, it is listed as a required runtime command and must be available in your `PATH`.

Plugins may also integrate with external services, such as PipeWire, D-Bus services, or another running
application. These integrations are documented in the plugin listing, but are not checked or provided
by nix-opendeck.
  
### Source Code and Licenses
nix-opendeck, via the binary cache, distributes builds of third-party open-source software under their
respective licenses. Additionally, the derivations ensure that upstream license files are added to the
build output.

The Nix derivations in this repository identify the upstream source revisions, dependencies, and build
instructions used to produce these packages. Any downstream patches are also included in this repository.

The source code for each package can be obtained through the upstream repositories referenced in its
derivation, using the specified version or commit.

For packages requiring corresponding source availability under licenses such as GPLv3 or MPL 2.0, please
consult the relevant derivation and its upstream source. If any referenced source is unavailable, please
open an issue so that the corresponding source can be provided.

The LICENSE file in the root of this repository applies to nix-opendeck's original packaging and integration code. Downstream patches to third-party projects are distributed in accordance with the applicable upstream licences. In particular, the modified OpenDeck application is distributed under GPL-3.0-or-later.

## Plugin Listing
Below is a list of the plugins where a derivation is included in this repo. You can check their 
upstream sources for more information.

### Action & Integration Plugins

Not every plugin is available on every platform. The flake filters the available plugins based
on their supported systems, so for example plugins focused on Linux-specific integrations like
PipeWire are not available on macOS.

| Upstream plugin | Package name | External integrations | Required runtime commands |
| --- | --- | --- | --- |
| [Starterpack](https://github.com/nekename/OpenDeck/tree/main/plugins/com.amansprojects.starterpack.sdPlugin) | `opendeck-plugins.nekename.starterpack` | - | - |
| [Analog Clock](https://github.com/elgatosf/streamdeck-analogclock/) | `opendeck-plugins.elgato.analogclock` | - | - |
| [Counter](https://github.com/OpenActionPlugins/counter) | `opendeck-plugins.openactionplugins.counter` | - | - |
| [Discord](https://github.com/OpenActionPlugins/discord) | `opendeck-plugins.openactionplugins.discord` | Discord IPC | - |
| [Linux App Launcher](https://github.com/OpenActionPlugins/desktopentry) | `opendeck-plugins.openactionplugins.desktopentry` | - | - |
| [MPRIS Media Controls](https://github.com/OpenActionPlugins/mpris) | `opendeck-plugins.openactionplugins.mpris` | MPRIS-compatible player | - |
| [System Information](https://github.com/OpenActionPlugins/system) | `opendeck-plugins.openactionplugins.system` | - | - |
| [Home Assistant](https://github.com/cgiesche/streamdeck-homeassistant) | `opendeck-plugins.cgiesche.homeassistant` | Home Assistant server | - |
| [Linux Uinput Simulation](https://github.com/Havner/uinput-simulation) | `opendeck-plugins.havner.uinput-simulation` | Linux uinput enabled (`.udev` rules included) | - |
| [Multi OBS Controller](https://github.com/theca11/multi-obs-controller) | `opendeck-plugins.theca11.multi-obs-controller` | OBS Studio | - |
| [OBS Tools](https://github.com/FeloDeck/obs-tools) | `opendeck-plugins.felodeck.obs-tools` | OBS Studio | - |
| [On Air Clock](https://github.com/wortkrieg/streamdeck-onairclock) | `opendeck-plugins.wortkrieg.onairclock` | - | - |
| [PipeWire Audio Control (Native)](https://github.com/sjourdois/opendeck-pipewire) | `opendeck-plugins.sjourdois.pipewire` | PipeWire | - |
| [PipeWire Audio Control](https://github.com/CronusAK/Pulse-Audio-Stream-Deck-Plugin) | `opendeck-plugins.cronusak.pipewire-audio` | PipeWire / WirePlumber | `wpctl`, `pw-dump`, `pactl` |
| [Redline Monitor](https://github.com/kahikara/opendeck-redline-monitor) | `opendeck-plugins.kahikara.redline-monitor` | See upstream | - |
| [Rotary Generic Command](https://github.com/babs/opendeck-plugins-rotary-command) | `opendeck-plugins.babs.rotary-command` | Rotary Encoder | - |
| [TikClock](https://github.com/GDWhisper/opendeck-tikclock) | `opendeck-plugins.gdwhisper.tikclock` | - | - |
| [Tomato Timer](https://github.com/gallowaylabs/streamdeck-tomato-timer) | `opendeck-plugins.gallowaylabs.tomato-timer` | - | - |
| [OpenDeck Weather](https://github.com/jfms7s/opendeck-weather) | `opendeck-plugins.jfms7s.weather` | - | - |
| [Volume Controller](https://github.com/mdvictor/opendeck-volume-controller) | `opendeck-plugins.mdvictor.volume-controller` | PulseAudio / PipeWire (via pipewire-pulse) | - |
| [Web Requests](https://github.com/data-enabler/streamdeck-web-requests) | `opendeck-plugins.data-enabler.web-requests` | - | - |
| [XIVDeck](https://github.com/KazWolfe/XIVDeck) | `opendeck-plugins.kazwolfe.xivdeck` | FFXIV / Dalamud | - |

### Device Support Plugins

These plugins extend OpenDeck's support to additional devices, including third-party Stream Deck alternatives.

Some devices require additional permissions on Linux. Where a plugin provides udev rules, its package exposes a `.udev` attribute that can be added to NixOS's `services.udev.packages`. Rules from bundled plugins are also included in the corresponding OpenDeck package's `.udev` attribute.

See [Device Access on NixOS](#device-access-on-nixos) for configuration instructions.

| Upstream plugin | Package name | Supported devices | Additional setup |
| --- | --- | --- | --- |
| [Ajazz AKP03 / Mirabox N3](https://github.com/4ndv/opendeck-akp03) | `opendeck-plugins."4ndv".akp03` | AKP03, Mirabox N3 and compatible devices | Udev rules (Linux) |
| [Ajazz AKP153 / Mirabox HSV293S](https://github.com/4ndv/opendeck-akp153) | `opendeck-plugins."4ndv".akp153` | AKP153, Mirabox HSV293S and compatible devices | Udev rules (Linux) |
