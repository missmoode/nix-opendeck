## Compatibility fix

**Affected package/plugin:**  
**Upstream repository:**  
**Upstream version/commit:**  
**Related issue or failed update:**

### Problem

Describe the observed compatibility problem, how to reproduce it, and why a downstream fix is necessary.

### Implementation

Explain what the fix changes and why this approach was chosen.

- [ ] Reused existing upstream functionality where possible
- [ ] Kept downstream patches minimal and focused
- [ ] Modified existing relevant patches rather than introducing overlapping ones
- [ ] Preserved upstream behaviour, defaults and policy except where strictly
  necessary for compatibility
- [ ] Avoided introducing unnecessary abstractions or fallback behaviour

### Manual verification (if applicable)

Describe any functional testing performed beyond the automated CI checks.

**Platform(s) tested on:**  
**Limitations or untested behaviour:**

### Additional notes

Document any upstream changes likely to affect this patch in future, whether the fix should eventually be submitted upstream, and any remaining maintenance concerns.

If the fix only works with a newer upstream version, include the patch repair and version update together rather than merging an incompatible patch into `main` independently.
