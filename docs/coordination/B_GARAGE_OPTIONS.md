# Garage options and body selection — B intent

User priority: fill available vertical space before paginating, unlock all garage
options, remove Compact, and ensure chassis/body selection preserves every other
selected part. Branch `codex/b-garage-options`, from main `cffc860`.

Parallel ownership: responsive pagination agent owns Customize/Garage screen layout
and independent sizing tests; presentation agent owns runtime/preview support for
all weapon/drive combinations with authored body; primary owns catalogue/profile,
compatibility/save handling, documentation and integration checks. Preserve mass
and power validity warnings; unlock selection rather than silently substitute parts.
No new speculative parts or simulated authority from UI.

Damage visuals intent remains separate and unimplemented on codex/b-component-damage.
Chassis catalogue scope is being clarified while independent layout work proceeds.
