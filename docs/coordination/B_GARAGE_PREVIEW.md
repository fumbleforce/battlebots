# B garage live preview

Intent to A: `codex/b-garage-preview`, based on main `2a9e70a`, reserves only
garage/customization screens, a reusable cosmetic preview, independent B fixtures
and B coordination docs. General menu/router, session, audio and world work can
continue independently. No input actions, content identity or wire changes.

Replace concept images in Garage and Customize with a lit, isolated 3D view of
the equipped draft. Use canonical validated chassis dimensions and the existing
primitive weapon presentation for all five families, with selected paint.
Mouse drag/keyboard rotation, wheel/key zoom and reset stay local to the preview.
Invalid drafts clear stale models and show validation reasons. No physics bodies,
authoritative bot, simulation commands or saved-file writes run in this viewport.
This is a primitive build preview, not completion of authored bot-art integration.

Acceptance: independent scene exercises every weapon, chassis/paint changes,
invalid/stale clearing, bounded controls and absence of collision/simulation.
Review rendered preview and actual Garage/Customize at 1280x720. Run baseline,
existing garage/profile/history checks and register the new independent scene.

Implemented: `GarageBotPreview.show_loadout(Dictionary)` renders only valid
equipped drafts and owns a separate World3D; camera operations never mutate the
draft. `reset_view`, `rotate_view` and `zoom_view` serve mouse, keyboard and reset
button controls. Source scenes share the existing weapon visual, without creating
MvpBot or DriveBody. The old preview-chip text was removed because highlighting a
catalogue candidate does not equip it. Concept thumbnails remain labelled.

Validation: Godot 4.7.2 baseline, independent preview scene (headless and D3D12),
garage history, profile, customization screens, menu kit and menu flow passed.
The independent scene covers all 15 chassis/weapon combinations, selected paint,
pre-tree draft loading, replacement/freeing, invalid clearing, bounded camera,
caller immutability and separate preview worlds without collision nodes.
Rendered Garage and Customize were inspected at 1280x720. Menu flow emitted the
already-tracked two-ObjectDB shutdown warning; no crash occurred in these checks.
Persistent manual sandbox: `res://scenes/dev/b_garage_preview.tscn` (F6), independent
of saved builds, sessions and authoritative physics.

Next B work: proposed-part stat comparisons, repair UX and garage text scaling;
authored model integration remains separate. This increment does not claim final
bot art, combat-feel acceptance or completion of the whole 1v1 game.
