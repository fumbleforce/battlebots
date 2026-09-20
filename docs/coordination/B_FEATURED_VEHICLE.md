# Featured vehicle selector and rotating showcase — B handoff

Branch: `codex/b-featured-vehicle`, based on shared main `9e54dcc`.
Owner B implements the requested prominent vehicle selection and assembled-bot
showcase. A owns general main/lobby flow and authoritative session integration.

B publishes a session-free `FeaturedVehicle` control with detached loadout
choices, caller-owned selected index, selection intent signals, explicit edit
locking/status, text scaling and a live `GarageBotPreview`. Automatic pedestal
rotation is opt-in with an accessible pause action; Garage manual behavior stays
unchanged. Current canonical primitive models remain accurately identified.

The narrow coordinated consumer changes replace main's static featured image
and the lobby's small selection affordance. Existing lobby request/acknowledgement,
phase/pending locks and server authority remain. A's existing rule accepts a
loadout change while ready and clears readiness; this UI will not invent a new
network rule. Main/profile selection is local and does not silently save drafts.

Allowed integration paths: main_menu.gd/main_menu.tscn, lobby.gd/lobby.tscn and
affected independent menu fixtures. B component, preview and dedicated fixtures
are B-owned. No transport, game rules, arena, audio or project settings changes.

Acceptance: visible canonical active build and next/previous selection; invalid
records never gain a valid preview or bypass validation; no per-frame rebuild;
caller-owned locks and accepted state preserved; no profile/disk mutation inside
the component; rotation pause/resume and hidden behavior; 720p/1080p/ultrawide at
100/150% text, keyboard/mouse, independent scenes and actual composed integration.

## Implemented contract and review

FeaturedVehicle.render accepts detached choices, a caller-owned selected index,
editable flag and status. Previous/Next emits selection_requested(index, draft);
no profile, disk or network writes occur inside the component. Empty selection is
neutral; unavailable records keep their real validation reasons. Incoming and
outgoing records are detached. Main accepts local selection; lobby retains Apply
and authoritative acknowledgement, now including cosmetics for paint-only changes.

GarageBotPreview.set_auto_rotate opts into shared model/pedestal rotation, with
Pause/Resume and hidden/manual-inspection suspension. Normal Garage/Customize
behavior stays manual. Models are reused on repeated refresh, including invalid
records so later error pages do not reset. Canonical primitive geometry is shared
with the existing weapon presentation; final authored bot assets remain open.

Three independent scenes cover the component, rotation and main/lobby consumers.
The consumer fixture uses a real local MvpSession host to verify submission,
paint-only acknowledgement, invalid rejection and phase/pending callback guards.
Selection itself never changes the host build. Layout checks include long names,
invalid records, full text scale and clipped lobby-body scroll extents.

Baseline, FEATURED VEHICLE, GARAGE SHOWCASE, B MENU TEXT GAME, MENU FLOW and
MENU MODE GUARD pass. The last mode-guard run reports two ObjectDB instances at
exit, consistent with the existing cleanup-warning gate; no crash or script error
occurred. This increment does not claim a general shutdown fix or new remote-play
acceptance. Published intent is f999cd4; completed source is integrated into main
under the feature commit on this branch.

Final FEATURED VEHICLE MENU and MAIN MENU FIT pass, including native D3D12
captures at 720p and layout checks at 1080p/ultrawide, 100/150% text. Main and
lobby accept 48-character names; invalid lobby choices retain readable paged
errors. Body scroll extent is checked against its visible page, catching overflow
that window-only bounds missed. Invalid repair hides generic rules temporarily;
valid choices retain rules. Locked unsubmitted choices remain explicitly labelled
as drafts. Legacy MENU KIT LOBBY passes with real UDP; preview, Customize and
catalogue text regressions also pass. Final baseline passes after scene cleanup.

Reproduce the composed render with Godot 4.7.2 and
`res://tests/presentation/featured_vehicle_menu_test.tscn -- --capture`.
Captures are written to `user://featured-*-150.png`. Keyboard Enter and mouse
activation travel through the actual input pipeline in FEATURED VEHICLE PASS.
Three new scenes are registered in check-presentation.ps1. No test writes loadouts
or changes the user's selected build after the fixture exits.
