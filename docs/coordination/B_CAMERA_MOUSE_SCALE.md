# Resolution-independent camera input — B intent

Branch `codex/b-camera-mouse-scale`, from main `8978fdf`. B investigates whether
baseline_preview's use of transformed mouse relative motion makes third-person
sensitivity depend on window/content scaling. Reproduce with real engine event
transforms and the existing input adapter before changing production behavior.

Allowed paths: B baseline_preview adapter, independent presentation test scene,
presentation test registration, and coordination/contracts/handoff documentation.
No drive, bot model, weapon, Customize, project input action or network API changes.
The active Sawblade task retains those model/drive/weapon paths.

Acceptance: equal physical mouse deltas produce equal orbit angles under viewport
scaling; independent X/Y sensitivity and inversion remain; menus/released controls
ignore mouse orbit; existing camera settings/input checks pass. This is a control
consistency fix, not human camera-feel acceptance or deferred spectator work.
