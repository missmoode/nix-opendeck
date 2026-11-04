# OpenDeck on Nix

nix-opendeck packages [OpenDeck](https://github.com/nekename/OpenDeck) for Nix, with a
curated selection of plugins alongside reusable helpers for packaging more.

OpenDeck plugins can be managed declaratively through Home Manager or wrapped into
custom OpenDeck packages. The project includes patches to support plugins loaded
directly from the Nix store.

This is useful on NixOS, where plugins installed through OpenDeck's GUI may fail because
they expect a conventional Linux environment. On other platforms, nix-opendeck still
provides declarative plugin management.

This is my first attempt at packaging software for Nix, made out of a personal need for
my Stream Deck to just work on NixOS. As such, I use it myself and will continue
maintaining it for as long as I do. In the spirit of Nix, I'm making it public and doing
what I can to make it useful for everyone.

As this began as both a personal tool and a learning exercise, I
[made use of LLM assistance during development](#llm-usage-disclosure).

> [!WARNING]
> Breaking changes may still happen for a little while, but I think it's very unlikely
> at this point. This README will remain an up-to-date source of truth.

<div align="center">

[Installation](#installation) | [Binary Cache](#binary-cache) | [Usage](#usage) |
[Custom Packages](#custom-opendeck-packages) | [Plugin Listing](#plugin-listing) | [Package your own plugins](./PLUGIN-PACKAGING.md)

</div>

## Quick Start

Add nix-opendeck to your flake inputs:

```nix
opendeck.url = "github:missmoode/nix-opendeck";
```

> [!NOTE]
> These examples assume your flake inputs are available to your NixOS or Home Manager
> modules. If you haven't already configured this, pass `inputs` through NixOS's
> `specialArgs` or Home Manager's `extraSpecialArgs`.

### Installing OpenDeck with plugins

The simplest way to install OpenDeck with your choice of plugins is to use
`wrapOpenDeck`. It assembles OpenDeck and your selected plugins into a single Nix
package, and works directly from the flake.

For example, on NixOS:

```nix
{ inputs, pkgs, ... }:
let
  opendeck = inputs.opendeck.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  customOpenDeck = opendeck.wrapOpenDeck {
    plugins = with opendeck.opendeck-plugins; [
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

The `wrapOpenDeck` helper also works with nix-darwin and standalone Nix installations.
See [Custom OpenDeck packages](#custom-opendeck-packages) for other ways to use it.

### Managing plugins with Home Manager

If you'd prefer to manage plugins individually, the Home Manager module installs them
into OpenDeck's plugin directory and can reload changed plugins without restarting the
application.

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

The Home Manager module installs OpenDeck by default, so you don't need to install it
separately. Some [device-support plugins](#device-support-plugins) need additional udev
rules.

## Packages and Scope

This flake provides three OpenDeck packages:

- `opendeck-core`: OpenDeck with Nix compatibility patches, without bundled plugins.
- `opendeck`: The default package, including the upstream StarterPack plugin.
- `opendeck-with-plugins`: Bundles all plugins available on the selected platform that
  do not declare [required runtime commands](#required-runtime-commands) or additional
  udev rules.

The plugin-containing packages are assembled from `opendeck-core` without recompiling
the application. Custom plugin bundles can also be created using `wrapOpenDeck`.

The `default` package output is an alias for `opendeck`.

nix-opendeck also provides third-party plugin derivations, a Home Manager module, and
udev rules for supported hardware. See the [Plugin Listing](#plugin-listing) for
available plugins.

While the goal is to stay close to upstream OpenDeck, this repository includes
downstream patches where necessary to address compatibility issues or make the
experience of using OpenDeck with Nix smoother. Some changes fix functionality that
would otherwise break, while others improve integration with tools like Home Manager.

I'm considering these changes on a case-by-case basis, with a preference for using the
existing upstream functionality where I can, and using small, maintainable patches where
I feel it's warranted. See
[OpenDeck Compatibility Patches](#opendeck-compatibility-patches) for the details,
including how externally managed plugins are protected from the GUI.

On NixOS, you could alternatively try using
[nix-ld](https://github.com/nix-community/nix-ld) to run unpatched plugins that expect
conventional Linux library and dynamic linker paths.

## Installation

### Supported Platforms

nix-opendeck currently targets Linux (`x86_64-linux` and `aarch64-linux`) and macOS on
Apple Silicon (`aarch64-darwin`). It's tested working on NixOS, and should also work on
nix-darwin or standalone Nix installations on supported systems.

> [!WARNING]
> I've only tested it on NixOS on x86_64. While everything seems to compile for the
> others, I don't have the hardware to check. If you're on Linux aarch64 or Apple
> Silicon and trying this out, you're welcome to open an issue and let me know if it
> works!

The Home Manager module is available on all supported platforms.

On Linux (including NixOS), OpenDeck requires setting appropriate permissions to access
supported USB devices, normally provided through udev rules. See
[Device Access](#device-access) for configuration instructions.

### Standalone OpenDeck

If you just want the package, and don't care about the module or flake stuff:

```bash
nix profile add github:missmoode/nix-opendeck#opendeck
```

On Linux, this won't automatically configure device permissions: you'll need to
[configure device access](#device-access) yourself.

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
`opendeck` and redistributable plugins on the supported platforms, allowing you to
download pre-built packages instead of compiling them locally.

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

On other systems with Nix installed, add the following to your Nix configuration
(usually at `/etc/nix/nix.conf` for a multi-user installation):

```ini
extra-substituters = https://nix-opendeck.cachix.org
extra-trusted-public-keys = nix-opendeck.cachix.org-1:twvVjvv6Xm9H/m9sD2YQfIDoeUZLWEX5CpokN2An9L8=
```

> [!NOTE]
> To benefit from the cache on your first installation, activate the new Nix settings
> before installing OpenDeck. Otherwise, OpenDeck may be compiled locally because the
> new cache configuration hasn't yet been activated.
>
> Cache hits also depend on matching Nix derivations. Overriding this flake's `nixpkgs`
> input with `inputs.nixpkgs.follows` may result in cache misses.

## Usage

### Custom OpenDeck packages

The `wrapOpenDeck` helper creates an OpenDeck package containing your chosen plugins. It
works independently of Home Manager and can be used with NixOS, nix-darwin, or
standalone Nix installations.

You can use the helper directly from the flake:

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

If you've applied an [overlay](#overlay), you can instead use `pkgs.wrapOpenDeck`:

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

**Using Home Manager:** You can also set `programs.opendeck.package` to a custom bundle,
with or without an overlay. Additional plugins can still be managed separately through
`programs.opendeck.plugins`.

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

The examples using `environment.systemPackages` demonstrate NixOS installation, but
`wrapOpenDeck` itself is also available on nix-darwin and standalone Nix installations.

The wrapper retains OpenDeck's desktop integration, command-line arguments, and built-in
autostart support. Bundled plugins are loaded directly from package resources instead of
being copied into the user's plugin directory. On Linux, they are provided through a
separate Nix store directory; on macOS, they are assembled into the application bundle
without recompiling OpenDeck.

If a bundled plugin provides udev rules, these are included in the resulting package's
`.udev` attribute on Linux. NixOS users must still install those rules through
`services.udev.packages`. Plugins installed separately through Home Manager do not
contribute rules to the OpenDeck package's `.udev` attribute.

Plugins may also depend on [runtime commands](#required-runtime-commands) or external
services that the wrapper does not automatically configure.

### Home Manager Module

The Home Manager module lets you declare plugins you'd like to use, and installs them
into OpenDeck's plugin directory via symlinks from the Nix store.

It can be used with standalone Home Manager, or as part of a NixOS or nix-darwin
configuration. See [Quick Start](#quick-start) for an example.

By default, the module installs this flake's `opendeck` package. You can change
`programs.opendeck.package` to use something else, such as `opendeck-core`. If you do
that and still want StarterPack, you'll need to declare
`opendeck-plugins.nekename.starterpack` in `programs.opendeck.plugins` yourself.

If `programs.opendeck.installPackage` is `false`, `programs.opendeck.package` should
still match the OpenDeck package you installed elsewhere. The module uses it to check
which plugins are already bundled and prevent accidental double-declarations, as well as
to target the correct executable for plugin reloads or an optional restart.

> [!IMPORTANT]
> Plugins managed by the Home Manager module are marked as externally managed. The
> OpenDeck package includes patches that prevent its plugin manager from updating or
> removing them.
>
> OpenDeck also skips automatic update checks for these plugins and for bundled plugins,
> since their updates are managed outside the graphical store.
>
> Plugins installed through the GUI are unaffected. The Home Manager module will refuse
> to overwrite a plugin it doesn't already manage.

Home Manager normally reloads individual plugins when their symlinks are added, removed
or changed. The reload preserves saved settings and profile assignments without
restarting OpenDeck. It does not reload plugins whose store paths are unchanged.

Set `programs.opendeck.reloadOnPluginChanges = false` to defer changes until the next
launch, or `programs.opendeck.restartOnPluginChanges = true` to request one restart
instead of individual reloads. Restart takes precedence when both are enabled. These
notifications do not detect changes to bundled plugins in `programs.opendeck.package`.

### Device Access

#### udev rules on NixOS

OpenDeck requires udev rules to access supported USB devices. The OpenDeck packages
expose a `.udev` attribute containing the core Stream Deck rules, along with any
additional rules provided by bundled plugins.

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

[Device support plugins](#device-support-plugins) installed separately, including
through Home Manager, may expose their own `.udev` packages. If a plugin requires
additional udev rules, add its `.udev` attribute to `services.udev.packages` as well.

#### udev rules on other Linux distributions

On Linux distributions other than NixOS, you'll need to install the required udev rules
manually to allow OpenDeck to access your device.

See the relevant step of OpenDeck's
[Linux installation instructions](https://github.com/nekename/OpenDeck#linux).

The udev rules for [device support plugins](#device-support-plugins) can usually be
found in their upstream repo.

### Manual plugin installation

OpenDeck looks for plugins within its config directory:

- Linux: `$XDG_CONFIG_HOME/opendeck/plugins/`
- macOS: `~/Library/Application Support/opendeck/plugins/`

You could symlink the plugins from the Nix store (or elsewhere) directly into there, and
the patched `opendeck` should be able to use them. However, without the Home Manager
module they will not be protected from modification through the GUI.

If you manage plugin symlinks yourself, notify a running OpenDeck instance after
changing or removing a plugin:

```bash
opendeck --reload-plugin com.example.plugin.sdPlugin
```

The command loads, reloads or unloads the selected plugin without deleting its saved
settings or profile assignments. Use `opendeck --restart-if-running` to restart the
whole application instead. Neither command starts an inactive OpenDeck instance.

If you would rather bundle your plugins than manage these symlinks, see
[Custom OpenDeck packages](#custom-opendeck-packages).

### Overlay

Overlays are optional. The Home Manager module and NixOS udev configuration work without
them, but an overlay lets you access OpenDeck, its plugins, and their udev rules through
your existing `pkgs` argument.

The flake provides two overlays which expose OpenDeck, its plugins, the `wrapOpenDeck`
helper, and their `udev` rules through your existing `pkgs` argument:

- **`inputs.opendeck.overlays.pinned` (recommended):** Uses the same pinned dependencies
  as nix-opendeck's CI builds, allowing packages to be substituted from the
  [binary cache](#binary-cache) when available.
- **`inputs.opendeck.overlays.default`:** Builds packages against your own Nixpkgs,
  allowing them to share dependencies with your system. This may result in cache misses
  and local compilation.

> [!IMPORTANT]
> To benefit from the binary cache when using `overlays.pinned`, do not set
> `opendeck.inputs.nixpkgs.follows = "nixpkgs"` in your flake inputs. Doing so overrides
> nix-opendeck's locked Nixpkgs revision, potentially producing different derivations
> from those published by CI.
>
> If you prefer to use your system's Nixpkgs, `overlays.default` is recommended instead.

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

If you're just using Home Manager, you can configure an overlay through your own Nixpkgs
instance.

Once applied, you can reference OpenDeck packages directly through `pkgs` in your Home
Manager configuration:

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
> If Home Manager uses a separate Nixpkgs instance on systems integrated with NixOS or
> nix-darwin, the overlay must also be applied to that instance. When
> `home-manager.useGlobalPkgs = true`, the system-level overlay is shared automatically.
>
> The Home Manager module uses nix-opendeck's own `opendeck` package by default,
> independently of the chosen overlay. Setting
> `programs.opendeck.package = pkgs.opendeck` ensures that it uses the overlay-provided
> package.
>
> Custom package overrides may also produce different store paths and require local
> compilation.

## Packaging Details

### OpenDeck Compatibility Patches

nix-opendeck applies a small collection of downstream patches to OpenDeck to improve
compatibility with Nix installations.

These patches:

- Support symlinked plugins in the immutable Nix store, including their assets and
  executable permissions.
- Load bundled plugins directly from package resources without copying them into the
  user's plugin directory, while protecting managed plugins from GUI modification and
  excluding them from automatic graphical-store update checks.
- Support an optional restart of an already-running OpenDeck instance after Home Manager
  changes declared plugin symlinks, without launching an inactive app.
- Preserve PATH entries supplied by Nix wrappers and explain the PATH requirement for
  OpenDeck's built-in autostart.
- Exclude managed plugin links and ownership metadata from configuration backups and
  preserve the current Home Manager links and ownership state on restore.

The Nix build also includes minor changes to identify itself and direct users to the
relevant plugin compatibility documentation.

### Plugin Compatibility Notes

**Plugins installed through OpenDeck's graphical plugin store may not work correctly on
NixOS.** Many plugins are distributed as precompiled binaries or depend on libraries and
executables being available in conventional filesystem locations, which NixOS does not
necessarily provide.

nix-opendeck provides Nix-packaged versions of selected plugins, including their
dependencies and compatibility fixes where necessary. Installing a plugin through
nix-opendeck rather than the graphical store may resolve these issues.

However, Nix-packaged plugins can also encounter problems due to immutable store paths,
missing runtime dependencies, system configuration, or nix-opendeck’s downstream
patches.

If you encounter a problem, the following sections may help identify its cause:

- **[Plugin Listing](#plugin-listing)** — Check whether a Nix-packaged version is
  available, along with its platform support and external requirements.
- **[Required Runtime Commands](#required-runtime-commands)** — Some plugins depend on
  commands being available in OpenDeck's runtime environment.
- **[Device Access](#device-access)** — USB devices may require additional udev rules.
- **[Home Manager Module](#home-manager-module)** — Information about declaratively
  managed plugins, installation conflicts, and plugin updates.
- **[Bundled Plugins](#bundled-plugins)** — How plugins bundled into OpenDeck differ
  from those installed separately.
- **[OpenDeck Compatibility Patches](#opendeck-compatibility-patches)** — An overview of
  changes made to upstream OpenDeck for Nix compatibility.

If you encounter bugs with packages produced by this repo, it might not be the fault of
the upstream projects, but a problem with nix-opendeck's derivation, one of my patches,
or OpenDeck's handling of them.

Be certain before contacting the upstream devs!

nix-opendeck is a personal packaging project maintained on a best-effort basis. I can't
promise compatibility with every plugin, nor ongoing support.

You can
[report an issue](https://github.com/missmoode/nix-opendeck/issues/new?template=bug-report.yml)
on nix-opendeck’s tracker if you’re sure it’s within this project’s remit, but I’m not
comfortable assuring guaranteed action in response.

### Bundled Plugins

Upstream OpenDeck copies bundled plugins into the user's plugin directory at startup
when they are missing or older. nix-opendeck instead loads bundled plugins directly from
their package resources, leaving existing user installations untouched.

The Home Manager module prevents declaring a plugin separately when it is already
bundled, and refuses to overwrite existing user-installed plugins.

When a plugin exists both in the package and in the user’s plugin directory, the
packaged version is selected when its manifest version is **newer than or equal to** the
user’s version; a newer user version wins. If the versions cannot be compared,
nix-opendeck retains the user installation rather than replacing it automatically.

A selected packaged plugin cannot be updated or removed through OpenDeck's graphical
plugin manager. Any shadowed user installation remains on disk and can become active
again if the plugin is removed from the package. Configuration backups retain ordinary
user-installed plugins, while managed plugin symlinks and package resources are handled
separately. If removing a newer user-installed plugin reveals a bundled version, restart
OpenDeck to refresh resources in existing profile instances.

Upstream OpenDeck includes the StarterPack plugin by default, so nix-opendeck's
`opendeck` package does as well. The `opendeck-core` package includes no bundled
plugins.

nix-opendeck assembles bundled packages from the same compiled `opendeck-core`
derivation. This means you can change the bundled plugins without recompiling OpenDeck
itself.

You can also create your own [custom bundles](#custom-opendeck-packages).

### Required runtime commands

Some plugins invoke external commands at runtime. When nix-opendeck does not provide
such a command as part of the plugin package, it is listed as a required runtime command
and must be available in your `PATH`.

Plugins may also integrate with external services, such as PipeWire, D-Bus services, or
another running application. These integrations are documented in the plugin listing,
but are not checked or provided by nix-opendeck.

## Plugin Listing

Below is a list of the plugins where a derivation is included in this repo. You can
check their upstream sources for more information.

### Action & Integration Plugins

Not every plugin is available on every platform. The flake filters the available plugins
based on their supported systems, so for example plugins focused on Linux-specific
integrations like PipeWire are not available on macOS.

<!--
| [Hyprstream](https://github.com/danmaxis/hyprstream) | `opendeck-plugins.danmaxis.hyprstream` | Hyprland | Action-dependent: `grim`, `slurp`, `wl-copy`, `wf-recorder`, `makoctl` / `dunstctl` |
| [Hyprstream Media](https://github.com/danmaxis/hyprstream) | `opendeck-plugins.danmaxis.hyprstream-media` | MPRIS / OBS Studio | `playerctl` (media actions) |
| [Hyprstream Monitors](https://github.com/danmaxis/hyprstream) | `opendeck-plugins.danmaxis.hyprstream-monitors` | Linux system metrics / OBS Studio | - |
-->

| Upstream plugin | Package name | External integrations | Required runtime commands |
| -- | -- | -- | -- |
| [Starterpack] | `opendeck-plugins.nekename.starterpack` | - | - |
| [Analog Clock][analog-clock] | `opendeck-plugins.elgato.analogclock` | - | - |
| [Counter][oacounter] | `opendeck-plugins.openactionplugins.counter` | - | - |
| [Discord][oadiscord] | `opendeck-plugins.openactionplugins.discord` | Discord IPC | - |
| [Linux App Launcher][oadesktopentry] | `opendeck-plugins.openactionplugins.desktopentry` | - | - |
| [MPRIS Media Controls][oampris] | `opendeck-plugins.openactionplugins.mpris` | MPRIS-compatible player | - |
| [System Information][oasystem] | `opendeck-plugins.openactionplugins.system` | - | - |
| [Home Assistant][homeassistant] | `opendeck-plugins.cgiesche.homeassistant` | Home Assistant server | - |
| [Linux Uinput Simulation][uinput-simulation] | `opendeck-plugins.havner.uinput-simulation` | Linux uinput enabled (`.udev` rules included) | - |
| [Multi OBS Controller][multi-obs-controller] | `opendeck-plugins.theca11.multi-obs-controller` | OBS Studio | - |
| [OBS Tools][obs-tools] | `opendeck-plugins.felodeck.obs-tools` | OBS Studio | - |
| [On Air Clock][onairclock] | `opendeck-plugins.wortkrieg.onairclock` | - | - |
| [PipeWire Audio Control (Native)][pipewire-native] | `opendeck-plugins.sjourdois.pipewire` | PipeWire | - |
| [PipeWire Audio Control][pipewire-audio] | `opendeck-plugins.cronusak.pipewire-audio` | PipeWire / WirePlumber | `wpctl`, `pw-dump`, `pactl` |
| [PWSoundDeck] | `opendeck-plugins.biviale.pwsounddeck` | PipeWire / PulseAudio | `pactl` |
| [Redline Monitor][redline-monitor] | `opendeck-plugins.kahikara.redline-monitor` | See upstream | - |
| [Rotary Generic Command][rotary-command] | `opendeck-plugins.babs.rotary-command` | Rotary Encoder | - |
| [TikClock] | `opendeck-plugins.gdwhisper.tikclock` | - | - |
| [Tomato Timer][tomato-timer] | `opendeck-plugins.gallowaylabs.tomato-timer` | - | - |
| [OpenDeck Weather][jfms7sweather] | `opendeck-plugins.jfms7s.weather` | - | - |
| [Volume Controller][volume-controller] | `opendeck-plugins.mdvictor.volume-controller` | PulseAudio / PipeWire (via pipewire-pulse) | - |
| [Web Requests][web-requests] | `opendeck-plugins.data-enabler.web-requests` | - | - |
| [XIVDeck] | `opendeck-plugins.kazwolfe.xivdeck` | FFXIV / Dalamud | - |

### Device Support Plugins

These plugins extend OpenDeck's support to additional devices, including third-party
Stream Deck alternatives.

Some devices require additional permissions on Linux. Where a plugin provides udev
rules, its package exposes a `.udev` attribute that can be added to NixOS's
`services.udev.packages`. Rules from bundled plugins are also included in the
corresponding OpenDeck package's `.udev` attribute.

See [Device Access](#device-access) for more information on installing udev rules.

| Upstream plugin | Package name | Supported devices | Additional setup |
| -- | -- | -- | -- |
| [Ajazz AKP03 / Mirabox N3][akp03] | `opendeck-plugins."4ndv".akp03` | AKP03, Mirabox N3 and compatible devices | Udev rules (Linux) |
| [Ajazz AKP153 / Mirabox HSV293S][akp153] | `opendeck-plugins."4ndv".akp153` | AKP153, Mirabox HSV293S and compatible devices | Udev rules (Linux) |
| [Ajazz AKP05 / Mirabox N4][akp05] | `opendeck-plugins.ambiso.akp05` | AKP05, Mirabox N4 and compatible devices | Udev rules (Linux) |

## Plugin packaging and contributions

nix-opendeck maintains a curated selection of plugins rather than attempting to package
the entire OpenDeck ecosystem.

I generally consider plugins for inclusion if I use them myself, they provide broadly
useful functionality, are particularly popular, or support commonly used hardware.

Contributions of new plugin packages are welcome, but inclusion in this repository is at
my discretion. In particular, packages that require substantial ongoing maintenance or
extensive downstream compatibility patches may be better maintained independently.

Developers are encouraged to publish their own plugin derivations using nix-opendeck's
exported packaging helpers, although using these helpers is not required. Independently
packaged plugins can be used with the Home Manager module or `wrapOpenDeck` without
being included in this repository.

See [Plugin Packaging Guide](./PLUGIN-PACKAGING.md) for instructions on independently
packaging and distributing plugins.

## Source Code and Licenses

nix-opendeck distributes builds of third-party open-source software through its binary
cache under their respective licenses, including required upstream license files in the
package outputs.

The derivations identify upstream source revisions, dependencies, and build
instructions, while downstream patches are included in this repository.

You can retrieve the original, unpatched OpenDeck source through Nix. For example, on
`x86_64-linux`:

```bash
nix build --no-link --print-out-paths \
  'github:missmoode/nix-opendeck#packages.x86_64-linux.opendeck-core.src'
```

For individual plugins, consult their derivations for the corresponding source. Some
plugins are packaged from prebuilt release archives rather than source code. For
licenses requiring corresponding source availability, such as GPLv3 or MPL 2.0, please
open an issue if any required source is unavailable.

The root `LICENSE` applies to nix-opendeck's original packaging and integration code.
Downstream patches are subject to their respective upstream licenses, and the modified
OpenDeck application is distributed under GPL-3.0-or-later.

## Security and Updates

nix-opendeck pins its Nixpkgs revision to provide reproducible builds and reliable
binary cache availability. As rebuilding and verifying reproducibility for the entire
package set is an expensive process, the revision is generally updated monthly.
Automated updaters are defined for OpenDeck and most plugins, and are checked daily in
CI.

I may make security-related updates outside of this schedule when relevant
vulnerabilities become known, but I haven’t implemented automatic alerts at this time.
Timely security fixes are therefore not guaranteed.

If you want to track a more recent Nixpkgs revision, you can use
[`overlays.default`](#overlay) or configure
`opendeck.inputs.nixpkgs.follows = "nixpkgs"`. This is likely to cause the provided
binary cache to miss, and require rebuilding locally.

## LLM Usage Disclosure

I **used LLM assistance** while developing this project. The main uses were to navigate
OpenDeck's code, work through understanding Nix packaging from scratch, develop Rust
patches (prior to this, my only experience with Rust was reading the book and playing
with ESP32 systems), and conversationally review implementation decisions.

Some parts of the project (including the Home Manager module and the GitHub Actions CI
workflows) were LLM-generated, with me directing development, testing, and iterating on
issues I found.

I've reviewed and tested the results where I can, but there might still be mistakes or
room for improvement. I'd very much welcome contributions or corrections.

## Reproducibility

The `opendeck` package and plugins get tested for reproducibility across their supported
platforms when their output paths change in a pull request. The checks independently
rebuild the affected derivations and compare their outputs bit-for-bit against a
reference build. Passing is required before merging into `main`.

The OpenDeck core build also runs Rust regression tests covering plugin source
selection, saved resource paths, and asset authorization.

This doesn't verify the entire dependency closure, or guarantee that everything operates
at runtime. I don't have the hardware to test it all, though during development I do
test everything in this repo that can be tested on a Stream Deck Mk2 and NixOS on
`x86_64-linux`.

<!-- Upstream plugin links -->

[akp03]: https://github.com/4ndv/opendeck-akp03
[akp05]: https://github.com/ambiso/opendeck-akp05
[akp153]: https://github.com/4ndv/opendeck-akp153
[analog-clock]: https://github.com/elgatosf/streamdeck-analogclock/
[homeassistant]: https://github.com/cgiesche/streamdeck-homeassistant
[jfms7sweather]: https://github.com/jfms7s/opendeck-weather
[multi-obs-controller]: https://github.com/theca11/multi-obs-controller
[oacounter]: https://github.com/OpenActionPlugins/counter
[oadesktopentry]: https://github.com/OpenActionPlugins/desktopentry
[oadiscord]: https://github.com/OpenActionPlugins/discord
[oampris]: https://github.com/OpenActionPlugins/mpris
[oasystem]: https://github.com/OpenActionPlugins/system
[obs-tools]: https://github.com/FeloDeck/obs-tools
[onairclock]: https://github.com/wortkrieg/streamdeck-onairclock
[pipewire-audio]: https://github.com/CronusAK/Pulse-Audio-Stream-Deck-Plugin
[pipewire-native]: https://github.com/sjourdois/opendeck-pipewire
[pwsounddeck]: https://github.com/biviale/pwsounddeck
[redline-monitor]: https://github.com/kahikara/opendeck-redline-monitor
[rotary-command]: https://github.com/babs/opendeck-plugins-rotary-command
[starterpack]: https://github.com/nekename/OpenDeck/tree/main/plugins/com.amansprojects.starterpack.sdPlugin
[tikclock]: https://github.com/GDWhisper/opendeck-tikclock
[tomato-timer]: https://github.com/gallowaylabs/streamdeck-tomato-timer
[uinput-simulation]: https://github.com/Havner/uinput-simulation
[volume-controller]: https://github.com/mdvictor/opendeck-volume-controller
[web-requests]: https://github.com/data-enabler/streamdeck-web-requests
[xivdeck]: https://github.com/KazWolfe/XIVDeck
