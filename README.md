# OpenDeck on Nix

nix-opendeck packages [OpenDeck](https://github.com/nekename/OpenDeck) and a 
selection of plugins for Nix, with patches to support immutable plugins in the 
Nix store. It provides declarative plugin management through both custom
bundled packages and Home Manager.

This is useful on NixOS, where plugins installed through OpenDeck's GUI may fail because they expect a conventional Linux environment. On other platforms,
nix-opendeck still provides declarative plugin management.

This is my first attempt at packaging software for Nix, made out of a personal
need for my Stream Deck to just work on NixOS. I make no promises to maintain
this long-term, but in the spirit of Nix, I'm making it public and doing what
I can to make it useful for everyone.

As this began as both a personal tool and a learning exercise, I [made use of
LLM assistance during development](#llm-usage-disclosure).

> [!WARNING]
> Breaking changes may still happen for a little while, but I think it's unlikely at this point. This README will remain up-to-date.

<div align="center">

[Quick Start](#quick-start) | [Installation](#installation) | [Usage](#usage) | [Custom Bundles](#custom-bundled-packages) | [Plugin Listing](#plugin-listing)

</div>

## Quick Start

For NixOS with Home Manager, add nix-opendeck to your flake inputs:

```nix
opendeck.url = "github:missmoode/nix-opendeck";
```

Import the Home Manager module and declare your plugins:

```nix
{ inputs, pkgs, ... }:
let
  opendeck-plugins = inputs.opendeck.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opendeck-plugins;
in
{
  imports = [
    inputs.opendeck.homeManagerModules.default
  ];

  programs.opendeck = {
    enable = true;
    plugins = with opendeck-plugins; [
      gallowaylabs.tomato-timer
    ];
  };
}
```

On NixOS, also install the device-access rules in your NixOS configuration:

```nix
{ inputs, pkgs, ... }:
{
  services.udev.packages = [
    inputs.opendeck.packages.${pkgs.stdenv.hostPlatform.system}.opendeck.udev
  ];
}
```

The Home Manager module installs OpenDeck by default; no overlay is required.
Some [device-support plugins](#device-support-plugins) need additional udev rules.
For prebuilt packages, see [Binary Cache](#binary-cache). Other installation methods
and configuration options are documented below.

**Using Nix without Home Manager, or prefer bundled plugins?**

You can use `wrapOpenDeck` to create a custom OpenDeck package containing your chosen plugins, without recompiling the application. It works on NixOS, nix-darwin, and standalone Nix installations, with or without Home Manager.

See [Custom bundled packages](#custom-bundled-packages) for examples.

## Packages and Scope

This flake provides three OpenDeck packages:

- `opendeck-core`: OpenDeck with Nix compatibility patches, without bundled plugins.
- `opendeck`: The default package, including the upstream StarterPack plugin.
- `opendeck-with-plugins`: Bundles all plugins available on the selected platform
  that do not declare [required runtime commands](#required-runtime-commands) or
  additional udev rules.

The plugin-containing packages are assembled from opendeck-core without recompiling the application. Custom plugin bundles can also be created using `wrapOpenDeck`.

The `default` package output is an alias for `opendeck`.

It also provides third-party plugin derivations, a Home Manager module, and udev
rules for supported hardware. See the [Plugin Listing](#plugin-listing) for available plugins.

While the goal is to stay close to upstream OpenDeck, this repository includes downstream
patches where necessary to address compatibility issues or make the experience of using
OpenDeck with Nix smoother. Some changes fix functionality that would otherwise break,
while others improve integration with tools like Home Manager.

I'm considering these changes on a case-by-case basis, with a preference for using the
existing upstream functionality where I can, and using small, maintainable patches where
I feel it's warranted. See [OpenDeck Compatibility Patches](#opendeck-compatibility-patches)
for the details, including how externally managed plugins are protected from the GUI.

On NixOS, you could alternatively try using [nix-ld](https://github.com/nix-community/nix-ld)
to run unpatched plugins that expect conventional Linux library and dynamic linker paths.

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
If you just want the package, and don't care about the module or flake stuff:

```bash
nix profile add github:missmoode/nix-opendeck#opendeck
```

This won't automatically configure device permissions: you'll need to [do that
yourself](#device-access-on-other-linux-distributions).

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

A binary cache is available on [Cachix](https://app.cachix.org/cache/nix-opendeck)
for `opendeck` and redistributable plugins on the supported platforms,
allowing you to download pre-built packages instead of compiling them locally.

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

On other systems with Nix installed, add the following to your Nix
configuration (usually at `/etc/nix/nix.conf` for a multi-user installation):

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

OpenDeck requires udev rules to access supported USB devices. The OpenDeck
packages expose a `.udev` attribute containing the core Stream Deck rules,
along with any additional rules provided by bundled plugins.

Install these rules through NixOS's standard `services.udev.packages` option:

```nix
{
  inputs,
  pkgs,
  ...
}:
let
  opendeck = inputs.opendeck.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
  opendeck-plugins = inputs.opendeck.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opendeck-plugins;
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

[Device support plugins](#device-support-plugins) installed separately,
including through Home Manager, may expose their own `.udev` packages. If a
plugin requires additional udev rules, add its `.udev` attribute to
`services.udev.packages` as well.

### Device access on other Linux distributions

On Linux distributions other than NixOS, you'll need to install the required
udev rules manually to allow OpenDeck to access your device.

See the relevant step of OpenDeck's [Linux installation instructions](https://github.com/nekename/OpenDeck#linux).

The udev rules for [device support plugins](#device-support-plugins) can
usually be found in their upstream repo.

### Home Manager Module

The Home Manager module lets you declare plugins you'd like to use, and
installs them into OpenDeck's plugin directory via symlinks from the Nix store.

It can be used with standalone Home Manager, or as part of a NixOS or
nix-darwin configuration. See [Quick Start](#quick-start) for an example.

By default, the module installs this flake's `opendeck` package. You can change
`programs.opendeck.package` to use something else, such as `opendeck-core`. If
you do that and still want StarterPack, you'll need to declare
`opendeck-plugins.nekename.starterpack` in `programs.opendeck.plugins`
yourself.

If `programs.opendeck.installPackage` is `false`, `programs.opendeck.package`
should still match the OpenDeck package you installed elsewhere. The module
uses it to check which plugins are already bundled and prevent accidental
double-declarations, as well as to target the correct executable for
plugin reloads or an optional restart.

> [!IMPORTANT]
> Plugins managed by the Home Manager module are marked as externally managed.
> The OpenDeck package includes patches that prevent its plugin manager from
> updating or removing them.
>
> OpenDeck also skips automatic update checks for these plugins and for bundled
> plugins, since their updates are managed outside the graphical store.
>
> Plugins installed through the GUI are unaffected. The Home Manager module
> will refuse to overwrite a plugin it doesn't already manage.

Home Manager normally reloads individual plugins when their symlinks are added,
removed or changed. The reload preserves saved settings and profile assignments
without restarting OpenDeck. It does not reload plugins whose store paths are
unchanged.

Set `programs.opendeck.reloadOnPluginChanges = false` to defer changes until the
next launch, or `programs.opendeck.restartOnPluginChanges = true` to request one
restart instead of individual reloads. Restart takes precedence when both are
enabled. These notifications do not detect changes to bundled plugins in
`programs.opendeck.package`.

### Usage without the Home Manager module

#### Using the plugin derivations

OpenDeck looks for plugins within its config directory:
- Linux: `$XDG_CONFIG_HOME/opendeck/plugins/`
- macOS: `~/Library/Application Support/opendeck/plugins/`

You could symlink the plugins from the Nix store (or elsewhere) directly into
there, and the patched `opendeck` should be able to use them. However, without
the Home Manager module they will not be protected from modification through
the GUI.

If you manage plugin symlinks yourself, notify a running OpenDeck instance
after changing or removing a plugin:

```bash
opendeck --reload-plugin com.example.plugin.sdPlugin
```

The command loads, reloads or unloads the selected plugin without deleting
its saved settings or profile assignments. Use `opendeck --restart-if-running`
to restart the whole application instead. Neither command starts an
inactive OpenDeck instance.

Alternatively, you can [bundle plugins](#custom-bundled-packages) into an
OpenDeck package using `wrapOpenDeck`. This lets you select plugins
declaratively without Home Manager, and without recompiling OpenDeck when the
plugin selection changes.

The `opendeck-with-plugins` package is also available as a convenience,
bundling all plugins supported on the selected platform that do not declare
additional runtime commands or udev rules.

### Custom bundled packages

The `wrapOpenDeck` helper creates an OpenDeck package containing your chosen
plugins. It works independently of Home Manager and can be used with NixOS,
nix-darwin, or standalone Nix installations.

With either [overlay](#overlay) applied, you can use `pkgs.wrapOpenDeck`:

```nix
{ pkgs, ... }:
let
  customOpenDeck = pkgs.wrapOpenDeck {
    plugins = with pkgs.opendeck-plugins; [
      nekename.starterpack
      openactionplugins.mpris
      gallowaylabs.tomato-timer
    ];
  };
in
{
  environment.systemPackages = [ customOpenDeck ];

  # NixOS only: install rules for supported devices.
  services.udev.packages = [ customOpenDeck.udev ];
}
```

**Using Home Manager:** You can also set `programs.opendeck.package` to a
custom bundle, with or without an overlay. Additional plugins can still be
managed separately through `programs.opendeck.plugins`.

```nix
{ inputs, pkgs, ... }:
let
  opendeck = inputs.opendeck.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.opendeck.homeManagerModules.default ];

  programs.opendeck = {
    enable = true;

    package = opendeck.wrapOpenDeck {
      plugins = with opendeck.opendeck-plugins; [
        nekename.starterpack
        openactionplugins.mpris
      ];
    };

    # Additional plugins can still be managed separately.
    plugins = with opendeck.opendeck-plugins; [
      gallowaylabs.tomato-timer
    ];
  };
}
```

Alternatively, you can use the helper directly from the flake without an
overlay or Home Manager:

```nix
{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  opendeck = inputs.opendeck;
  plugins = opendeck.legacyPackages.${system}.opendeck-plugins;

  customOpenDeck = opendeck.legacyPackages.${system}.wrapOpenDeck {
    plugins = with plugins; [
      nekename.starterpack
      openactionplugins.mpris
      gallowaylabs.tomato-timer
    ];
  };
in
{
  environment.systemPackages = [ customOpenDeck ];
  services.udev.packages = [ customOpenDeck.udev ];
}
```

The examples using `environment.systemPackages` demonstrate NixOS
installation, but `wrapOpenDeck` itself is also available on nix-darwin and
standalone Nix installations.

The wrapper retains OpenDeck's desktop integration, command-line arguments,
and built-in autostart support. Bundled plugins are loaded directly from
package resources instead of being copied into the user's plugin directory. On
Linux, they are provided through a separate Nix store directory; on macOS,
they are assembled into the application bundle without recompiling OpenDeck.

If a bundled plugin provides udev rules, these are included in the resulting
package's `.udev` attribute on Linux. NixOS users must still install those
rules through `services.udev.packages`. Plugins installed separately through
Home Manager do not contribute rules to the OpenDeck package's `.udev`
attribute.

Plugins may also depend on [runtime commands](#required-runtime-commands) or
external services that the wrapper does not automatically configure.

### Overlay

Overlays are optional. The Home Manager module and NixOS udev configuration
work without them, but an overlay lets you access OpenDeck, its plugins, and
their udev rules through your existing `pkgs` argument.

The flake provides two overlays which expose OpenDeck, its plugins, the
`wrapOpenDeck` helper, and their `udev` rules through your existing `pkgs`
argument:
- **`inputs.opendeck.overlays.pinned` (recommended):** Uses the same pinned
  dependencies as nix-opendeck's CI builds, allowing packages to be
  substituted from the [binary cache](#binary-cache) when available.
- **`inputs.opendeck.overlays.default`:** Builds packages against your own
  Nixpkgs, allowing them to share dependencies with your system. This may
  result in cache misses and local compilation.

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

If you're just using Home Manager, you can configure an overlay through your
own Nixpkgs instance.

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
> If Home Manager uses a separate Nixpkgs instance on systems integrated with
> NixOS or nix-darwin, the overlay must also be applied to that instance. When
> `home-manager.useGlobalPkgs = true`, the system-level overlay is shared
> automatically.
> 
> The Home Manager module uses nix-opendeck's own `opendeck` package by
> default, independently of the chosen overlay.
> Setting `programs.opendeck.package = pkgs.opendeck` ensures that it uses the
> overlay-provided package.
>
> Custom package overrides may also produce different store paths and require
> local compilation.

## Packaging Details
### OpenDeck Compatibility Patches

nix-opendeck applies a small collection of downstream patches to OpenDeck to
improve compatibility with Nix installations.

These patches:
- Support symlinked plugins in the immutable Nix store, including their assets
  and executable permissions.
- Load bundled plugins directly from package resources without copying them
  into the user's plugin directory, while protecting managed plugins from GUI
  modification and excluding them from automatic graphical-store update checks.
- Support an optional restart of an already-running OpenDeck instance after
  Home Manager changes declared plugin symlinks, without launching an inactive app.
- Preserve PATH entries supplied by Nix wrappers and explain the PATH
  requirement for OpenDeck's built-in autostart.
- Exclude managed plugin links and ownership metadata from configuration
  backups and preserve the current Home Manager links and ownership state on
  restore.

The Nix build also includes minor changes to identify itself and direct users to the relevant
plugin compatibility documentation.

### Plugin Compatibility Notes

**Plugins installed through OpenDeck's graphical plugin store may not work correctly on NixOS.**
Many plugins are distributed as precompiled binaries or depend on libraries
and executables being available in conventional filesystem locations, which
NixOS does not necessarily provide.

nix-opendeck provides Nix-packaged versions of selected plugins, including
their dependencies and compatibility fixes where necessary. Installing a
plugin through nix-opendeck rather than the graphical store may resolve these
issues.

However, Nix-packaged plugins can also encounter problems due to immutable
store paths, missing runtime dependencies, system configuration, or downstream
OpenDeck patches.

If you encounter a problem, the following sections may help identify its cause:

- **[Plugin Listing](#plugin-listing)** — Check whether a Nix-packaged version
  is available, along with its platform support and external requirements.
- **[Required Runtime Commands](#required-runtime-commands)** — Some plugins
  depend on commands being available in OpenDeck's runtime environment.
- **[Device Access on NixOS](#device-access-on-nixos)** — USB devices may
  require additional udev rules. For other distributions, see [Device Access on Other Linux Distributions](#device-access-on-other-linux-distributions).
- **[Home Manager Module](#home-manager-module)** — Information about
  declaratively managed plugins, installation conflicts, and plugin updates.
- **[Bundled Plugins](#bundled-plugins)** — How plugins bundled into OpenDeck
  differ from those installed separately.
- **[OpenDeck Compatibility Patches](#opendeck-compatibility-patches)** — An
  overview of changes made to upstream OpenDeck for Nix compatibility.

If you encounter bugs with packages produced by this repo, it might not be the
fault of the upstream projects, but a problem with nix-opendeck's derivation,
one of my patches, or OpenDeck's handling of them.

Be certain before contacting the upstream devs!

nix-opendeck is a personal packaging project maintained on a best-effort
basis. I can't promise compatibility with every plugin, nor ongoing support.

### Bundled Plugins

Upstream OpenDeck copies bundled plugins into the user's plugin directory at
startup when they are missing or older. nix-opendeck instead loads bundled
plugins directly from their package resources, leaving existing user
installations untouched.

When a plugin exists in multiple places, Home Manager-managed installations
take precedence. Otherwise, the packaged version is selected when its manifest
version is **newer than or equal to** the user's version; a newer user version
wins. If a user installation's version cannot be compared, nix-opendeck leaves
it in place rather than replacing it automatically. The Home Manager module
also prevents declaring a plugin separately when it is already bundled.

A selected packaged plugin cannot be updated or removed through OpenDeck's
graphical plugin manager. Any shadowed user installation remains on disk and
can become active again if the plugin is removed from the package.
Configuration backups retain ordinary user-installed plugins, while managed
plugin symlinks and package resources are handled separately. If removing a
newer user-installed plugin reveals a bundled version, restart OpenDeck to
refresh resources in existing profile instances.

Upstream OpenDeck includes the StarterPack plugin by default, so
nix-opendeck's `opendeck` package does as well. The `opendeck-core` package
includes no bundled plugins.

nix-opendeck assembles bundled packages from the same compiled `opendeck-core`
derivation. This means you can change the bundled plugins without recompiling
OpenDeck itself.

You can also create your own [custom bundles](#custom-bundled-packages).

### Required runtime commands
Some plugins invoke external commands at runtime. When nix-opendeck does not
provide such a command as part of the plugin package, it is listed as a
required runtime command and must be available in your `PATH`.

Plugins may also integrate with external services, such as PipeWire, D-Bus
services, or another running application. These integrations are documented in
the plugin listing, but are not checked or provided by nix-opendeck.

## Plugin Listing
Below is a list of the plugins where a derivation is included in this repo.
You can check their upstream sources for more information.

### Action & Integration Plugins

Not every plugin is available on every platform. The flake filters the
available plugins based on their supported systems, so for example plugins
focused on Linux-specific integrations like PipeWire are not available on
macOS.

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

These plugins extend OpenDeck's support to additional devices, including
third-party Stream Deck alternatives.

Some devices require additional permissions on Linux. Where a plugin provides
udev rules, its package exposes a `.udev` attribute that can be added to
NixOS's `services.udev.packages`. Rules from bundled plugins are also included
in the corresponding OpenDeck package's `.udev` attribute.

See [Device Access on NixOS](#device-access-on-nixos) for configuration instructions.

| Upstream plugin | Package name | Supported devices | Additional setup |
| --- | --- | --- | --- |
| [Ajazz AKP03 / Mirabox N3](https://github.com/4ndv/opendeck-akp03) | `opendeck-plugins."4ndv".akp03` | AKP03, Mirabox N3 and compatible devices | Udev rules (Linux) |
| [Ajazz AKP153 / Mirabox HSV293S](https://github.com/4ndv/opendeck-akp153) | `opendeck-plugins."4ndv".akp153` | AKP153, Mirabox HSV293S and compatible devices | Udev rules (Linux) |

## Source Code and Licenses
nix-opendeck, via the binary cache, distributes builds of third-party
open-source software under their respective licenses. Additionally, the
derivations ensure that upstream license files are added to the build output.

The Nix derivations in this repository identify the upstream source revisions,
dependencies, and build instructions used to produce these packages. Any
downstream patches are also included in this repository.

The source code for each package can be obtained through the upstream
repositories referenced in its derivation, using the specified version or
commit.

For packages requiring corresponding source availability under licenses such
as GPLv3 or MPL 2.0, please consult the relevant derivation and its upstream
source. If any referenced source is unavailable, please open an issue so that
the corresponding source can be provided.

The LICENSE file in the root of this repository applies to nix-opendeck's
original packaging and integration code. Downstream patches to third-party
projects are distributed in accordance with the applicable upstream licenses.
In particular, the modified OpenDeck application is distributed under
GPL-3.0-or-later.

## Security and Updates

nix-opendeck pins its Nixpkgs revision to provide reproducible builds and
reliable binary cache availability. As rebuilding and verifying
reproducibility for the entire package set is an expensive process, the
revision is generally updated monthly. Automated updaters are defined for
OpenDeck and most plugins, and are checked daily in CI.

I may make Security-related updates outside of this schedule when relevant
vulnerabilities become known, but I haven’t implemented automatic alerts at
this time. Timely security fixes are therefore not guaranteed.

If you want to track a more recent Nixpkgs revision you can use
[`overlays.default`](#overlay) or configure 
`opendeck.inputs.nixpkgs.follows = "nixpkgs"`. This is likely to cause the
provided binary cache to miss, and require rebuilding locally.

## LLM Usage Disclosure

I **used LLM assistance** while developing this project. The main uses were
to navigate OpenDeck's code, work through understanding Nix packaging from
scratch, develop Rust patches (prior to this, my only experience with Rust
was reading the book and playing with ESP32 systems), and conversationally
review implementation decisions.

Some parts of the project (the Home Manager module, and the
GitHub workflow CI), were LLM-generated, with me directing development,
testing, and iterating on issues I found.

I've tested the results where I can, but there might still be mistakes
or room for improvement. I'd very much welcome contributions or corrections.

## Reproducibility

The `opendeck` package and plugins get tested for reproducibility across their
supported platforms when their output paths change in a pull request. The
checks independently rebuild the affected derivations and compare their outputs
bit-for-bit against a reference build. Passing is required before merging into
`main`.

The OpenDeck core build also runs Rust regression tests covering plugin source
selection, saved resource paths, archive validation, and asset authorization.

This doesn't verify the entire dependency closure, or guarantee that everything
operates at runtime. I don't have the hardware to test it all, though during
development I do test everything in this repo that can be tested on a 
Stream Deck Mk2 and NixOS on `x86_64-linux`.
