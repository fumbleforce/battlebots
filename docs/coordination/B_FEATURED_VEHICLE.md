# Featured vehicle selector and rotating showcase — B intent

Branch: `codex/b-featured-vehicle`, based on shared main `9e54dcc`.
Owner B implements the requested prominent vehicle selection and assembled-bot
showcase. A owns general main/lobby flow and authoritative session integration.

B will publish a session-free `FeaturedVehicle` control with detached loadout
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
