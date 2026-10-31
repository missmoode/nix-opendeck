## New plugin

nix-opendeck maintains a curated selection of plugins rather than attempting to package the entire OpenDeck ecosystem. Independent packaging is generally preferred; see the [Plugin Packaging Guide](/PLUGIN-PACKAGING.md).

Please explain why this plugin would be a useful addition to the main repository.

**Plugin:**  
**Upstream repository:**  
**Upstream version/tag:**  
**Packaging helper:** `mkRustOpenDeckPlugin` / `mkNpmOpenDeckPlugin` / other

**Reason for inclusion:**

Why should this plugin be maintained in nix-opendeck rather
than independently? Consider its general usefulness, popularity
or support for commonly used hardware.

### Implementation

Briefly describe the packaging approach and anything unusual about this plugin.

- [ ] Added derivation under `src/packages/plugins/`
- [ ] Registered plugin in `src/packages/plugins/default.nix`
- [ ] Configured release updates where appropriate
- [ ] Documented required commands, services or udev rules, if applicable
- [ ] Any downstream patches are necessary, minimal and documented
- [ ] Avoided unrelated changes to upstream behaviour and defaults

### Licensing and redistribution

**Upstream license:**  
**License source (URL):**  
**Redistributable:** Yes / No / Unclear

- [ ] Declared the appropriate license in `meta.license`
- [ ] Checked redistribution rights for bundled binaries, assets and dependencies
- [ ] Included required license notices, where applicable

**Licensing concerns or redistribution restrictions:**

### Manual verification

Describe any functional testing performed beyond the automated
CI checks, or explain why testing wasn't possible.

**Platform(s) tested on:**  
**Limitations or untested behaviour:**

### Additional notes

Anything worth remembering when maintaining or updating this plugin.
