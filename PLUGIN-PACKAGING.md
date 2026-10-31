# Packaging OpenDeck plugins independently

nix-opendeck provides reusable Nix packaging helpers and supports plugins built
outside this repository.

This guide covers packaging and publishing your own plugin. For the plugins
maintained by this repository, see the [plugin listing](./README.md#plugin-listing).
For installing OpenDeck itself, see the [README](./README.md#installation).

## Plugin package requirements

A compatible plugin derivation should:
- Install its plugin directory at `$out/<pluginId>/`, with `manifest.json` immediately
  inside it. The `pluginId` must be the directory name OpenDeck expects, for example
  `com.example.plugin.sdPlugin`.
- Expose `passthru.pluginId` containing that directory name. The helpers do this
  automatically.
- Include the plugin's required assets and executables in the paths expected by its
  manifest. Executables must be runnable on the target platform.
- Declare accurate platform and license metadata. Include upstream license files in
  the output where appropriate.

For example, a completed derivation might have this layout:
```
result/
└── com.example.plugin.sdPlugin/
    ├── manifest.json
    ├── icons/
    └── ...
```
The helpers check that a `manifest.json` file exists and contains a JSON object.
**They do not guarantee the plugin will work in OpenDeck.** You still need to check
its runtime dependencies, manifest paths, and actual behaviour.

## Choosing a packaging helper

The public helpers are available through `inputs.opendeck.lib`. Each one takes a
Nixpkgs package set first, and then the plugin definition.

| Helper | Intended use | Important plugin-specific attributes |
| --- | --- | --- |
| `mkPrebuiltOpenDeckPlugin` | Sources or release archives containing an already-built plugin | `pluginDir` |
| `mkRustOpenDeckPlugin` | Plugins compiled with Cargo | `binaryName`, `binaryInstallPath`; optionally `binaryPath`, `assetsDir` |
| `mkNpmOpenDeckPlugin` | Plugins built using npm | `pluginDir`, and the usual `buildNpmPackage` inputs such as `npmDepsHash` |
| `mkYarnOpenDeckPlugin` | Plugins built using Yarn | `pluginDir`, `yarnDepsHash`; optionally `yarnBuildScript` |
| `mkOpenDeckPlugin` | Common installation logic for custom derivations | `pluginId`, `installPlugin` |

While every other helper constructs a derivation, `mkOpenDeckPlugin` is lower-level:
it returns attributes for use in a derivation you construct yourself.

These helpers build on ordinary Nixpkgs packaging functions. You can supply their
usual attributes, such as `src`, native and runtime build inputs, patches, and build
hooks. You can also write a compatible derivation without using the helpers.

See the [helper definitions](./src/lib/plugins/) and [existing plugin
packages](./src/packages/plugins/) for more varied examples.

## Example: an independent plugin flake

The following example packages Elgato's Analog Clock plugin, which is already included
in nix-opendeck, but works well to explain.

Create a `flake.nix` in your own Git repository:
```nix
{
  description = "Independent OpenDeck plugin package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    opendeck.url = "github:missmoode/nix-opendeck";
  };

  outputs = { nixpkgs, opendeck, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    in
    {
      packages = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          mkPrebuiltOpenDeckPlugin = opendeck.lib.mkPrebuiltOpenDeckPlugin pkgs;
        in
        {
          default = mkPrebuiltOpenDeckPlugin (finalAttrs: {
            pname = "opendeck-example-analogclock";
            version = "2.0.0";

            src = pkgs.fetchFromGitHub {
              owner = "elgatosf";
              repo = "streamdeck-analogclock";
              rev = "ecbdf69ed335d57de21e77968a0b536b04bfa662";
              hash = "sha256-WGe/q5OGRhSL9OO9orWw1Ozj1enYDQMBGxl9wxgccrg=";
            };

            pluginId = "com.elgato.analogclock.sdPlugin";
            pluginDir = "Sources/${finalAttrs.pluginId}";
            licenseFiles = [ "LICENSE" ];

            meta = {
              description = "Analog clock plugin for OpenDeck";
              homepage = "https://github.com/elgatosf/streamdeck-analogclock";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.linux ++ [ "aarch64-darwin" ];
            };
          });
        }
      );
    };
}
```

Here, `pluginDir` points to the directory *inside the unpacked source* that contains
`manifest.json`. The `mkPrebuiltOpenDeckPlugin` helper copies its contents to
`$out/${pluginId}/`. For your own plugin, inspect the upstream archive or checkout
rather than assuming the same layout.

Add the flake to Git, then build and inspect the output:
```bash
git add flake.nix
nix build '.#default'
test -f result/com.elgato.analogclock.sdPlugin/manifest.json
```

You can also inspect the exported identifier with:
```bash
nix eval --raw .#packages.x86_64-linux.default.pluginId
```

Replace `x86_64-linux` with your target system where necessary. Once the package
works, commit `flake.nix` and `flake.lock` and publish the repository. Consumers
can add it as a normal flake input; you do not need to publish it through
nix-opendeck.

## Using an independently packaged plugin

Once published, another user can add your repository as a flake input:
```nix
inputs = {
  opendeck.url = "github:missmoode/nix-opendeck";
  my-plugin.url = "github:example/my-opendeck-plugin";
};
```

Then use the package with Home Manager:
```nix
{ inputs, pkgs, ... }:
{
  imports = [
    inputs.opendeck.homeManagerModules.default
  ];

  programs.opendeck = {
    enable = true;
    plugins = [
      inputs.my-plugin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
```

The same plugin derivation can also be passed to `wrapOpenDeck` when creating a
bundled package. See [Custom bundled packages](./README.md#custom-bundled-packages).

## Runtime requirements and device permissions

Packaging a plugin does not automatically provide external services or every
executable it invokes. There are some recommended practices for dealing with
your requirements:

- Include libraries and tools that should be packaged with the plugin using
  normal Nixpkgs mechanisms where practical. Spooky Nix magic will reuse dependencies
  already available in the store, download them from a binary cache where available,
  or build them locally.
  - If your plugin invokes other executables, make sure it can actually locate them
    at runtime. Merely adding packages to `buildInputs` does not make their commands
    available in OpenDeck's environment.
  - Generally, it's a good idea to package tools where your plugin may be sensitive
    to a specific version for functionality or reproducibility.
  - Windows-based plugins may require Wine installed separately and accessible in
    OpenDeck's runtime environment. It's probably best not to include it directly
    in your derivation.
  - Deno is a pain about this. You'll know what I mean if you try and package with
    it.
- If the plugin depends on commands supplied by the user's environment, declare
  `requiredCommands = [ "some-command" ];` and document how to provide them.
  This metadata does **not** install commands or verify their availability at
  activation time.
  - Within nix-opendeck's own plugin catalogue, it's also used to exclude plugins
    with external command requirements from the `opendeck-with-plugins` convenience
    bundle.
- Make sure you document external services or applications needed by the plugin
  (for example OBS studio, Discord, or an MPRIS-compatible media player). The
  helpers do not provision these services, but it's useful to ensure that your users
  are aware.
- For Linux device plugins requiring additional rules, the helpers accept
  `udevRules`, mapping rule filenames to source paths. This exposes a separate
  udev rules package through the plugin's `.udev` attribute. On NixOS, users can add
  it to `services.udev.packages`.
  - A custom bundle made via `wrapOpenDeck` will expose the combined rules
    under its own `.udev` package attribute.
  - Installing a plugin through Home Manager does not automatically install
    system udev rules.

Only declare platforms you can reasonably support, and test device access and
executable behaviour on the relevant platform when possible.

## Maintaining and publishing your package
- Prefer fixed upstream revisions or release tags with hashes, and commit your
  `flake.lock`. Do not fetch a moving branch as if it were a fixed release.
- Respect upstream licenses, including requirements around redistribution and
  included license files. A successful local build does not by itself establish
  that you can redistribute the binary via a cache, legally speaking.
- Test both the Nix build and the actual plugin in OpenDeck. In particular, check
  icons/assets, plugin startup, its actions and any external integrations. **Make
  sure to check the plugin's logs for errors!**
- You'll need to maintain your own updates and compatibility fixes, and optionally a
  binary cache. For a small plugin package, manual updates may be sufficient. If
  maintenance becomes more involved, it might be a good idea to look into automation
  via GitHub workflows or similar.

### Tracking updates

For plugins maintained within nix-opendeck, verify that the package's update script
follows upstream's actual release mechanism. The packaging helpers provide a default
`nix-update` script, but this does not guarantee correct version discovery.

Where upstream consistently publishes GitHub Releases, prefer the existing
`nix-update-script` with `--use-github-releases`. For unusual
release/versioning schemes, use the simplest reliable alternative. If
automatic updates are not practical, explicitly set
`passthru.updateScript = null;` and maintain the package manually.

Test an updater with `nix-update ATTRIBUTE --flake --use-update-script`
before relying on the repository's automated update workflow.

### Inclusion in the nix-opendeck repo

If you'd like to propose your plugin for inclusion in nix-opendeck's repo, see the
[plugin listing](./README.md#plugin-listing),
[plugin contribution policy](./README.md#plugin-packaging-and-contributions),
and the [new plugin PR template](./.github/PULL_REQUEST_TEMPLATE/new-plugin.md).
Independently maintaining your own package is generally preferred. For inclusion in
nix-opendeck's repo, I may consider plugins that:
- Provide broadly useful Stream Deck functionality
- Are particularly popular
- Support commonly used hardware
