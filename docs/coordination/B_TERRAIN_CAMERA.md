# Terrain-aware camera clearance — B intent

Branch codex/b-terrain-camera, from f570bf9. B is investigating the third-person
camera's fixed floor-height assumption against A's newly published Moon terrain.
A owns terrain/world geometry; B owns camera pivot and boom collision behavior.

Hypothesis to reproduce independently: a rolled bot's camera anchor can lie in
raised ground even when its collision body is clear. Existing starting-overlap
handling collapses the boom at that anchor, potentially leaving the view embedded.
Use actual Jolt terrain queries and deterministic nonpenetrating bot placements.
Only change camera presentation after reproduction. Preserve world geometry,
gravity, drive, models, networking and the BotSource API. The active Sawblade/legs
task owns drive/model work and is not modified by this branch.

Acceptance: camera sphere outside raised terrain for upright/rolled/inverted
sources; no upward teleport through ceilings or perimeter walls; existing bot
contact, normal Foundry boom, recenter and camera settings regressions; independent
scene with real collision and clear limits on fixture vs human gameplay evidence.
