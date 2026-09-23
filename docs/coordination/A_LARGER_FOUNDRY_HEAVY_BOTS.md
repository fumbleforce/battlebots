# Larger Foundry and heavier machines — coordinated A/B change

Requested 23 September 2026, base `45f678b`, branch
`codex/a-larger-foundry-heavy-bots`. This session owns the explicitly requested
world/menu changes and bot physics tuning as one coordinated increment.

Allowed paths: Foundry geometry/visuals, arena bounds and their spawn/camera/bot
consumers, arena-selection captures/data, MvpBot/DriveBody/DriveModel and authored
weapon impulses, targeted tests, shared version/handoff documentation.
No bot models, garage interfaces or input bindings are being redesigned.

Plan: Foundry 100 m across opposing faces (twice its prior linear extent), Moon
remaining 50 m; true native arena previews; stronger resistance to tumbling and
less bouncing/impact knockback while retaining the existing strong acceleration,
steering and useful weapons. The user specifically selected impacts, bouncing
and tipping rather than motor response.
Publish arena extent through the authoritative world and camera-anchor metadata
so no client camera or fallback logic clamps to the old Foundry boundary.

Gameplay changes require a new build identity and matching client/server release.
Keep protocol/schema/catalogue unchanged unless their actual records change.
Validation: native rendered review, actual wall/spawn/recovery bounds, physics
handling and weapon checks, impaired contact prediction, natural duel, packaged
workers and external hosted private/Quick Play results/rematch. Human handling
feel remains a playtest judgement. Results and final tuning will be recorded here.

Implementation: Foundry floor, collision, spawns, floor markings, galleries and
roof now fit the 100 m octagon. Human-scale galleries repeat twice per face.
Moon retains its 50 m shell, heightfield and spawn positions. Preview assets are
1600×900 native production-scene renders, reproducible with
`godot --path battlebots --script res://tools/capture_arena_previews.gd`.
Both renders were visually reviewed.

Impact tuning keeps budget mass, damage, motor/steering settings and charged
lifter strength. Ballast is lowered by 20% of hull height; pitch/roll inertia
is 1.8 times the enclosing hull inertia, angular damping 0.45, friction 0.04
and restitution zero. Ordinary authored weapon impulses use 65% strength and
relative attacker/target mass. A 25% heavier target receives 20% less velocity
from the same strike without increasing recoil. B's drive model additionally
consumes the explicit center of mass for correct airborne replay. This is the
documented A/B prediction boundary handoff; no input or wire schema changed.

Measured Jolt checks: same pitch/roll pulse produces 2.490 versus 4.003 rad/s
(previous automatic inertia), a level two-meter drop lands without rebound,
and paid self-righting still works. Standard wheels reach 8.144 m/s in 1 s,
9.993 m/s in 1.4 s; pivot reaches 1.411 rad/s in 0.75 s, braking from 10 m/s
takes 5.400 m. Airborne replay is within 0.0001 m / 0.05 degrees over 250 ms
at fixed 60 Hz. Strong motor acceptance thresholds remain unchanged.

Release validation and exact artifact/image evidence follow below. Human
judgement of the new impact feel remains a playtest item.

Validation before packaging: baseline/import; Foundry geometry; all-mode heavy
spawn clearance in both arenas; heavy drive/impacts; combat physics; spinner
physical impulses and target-mass comparison; walker; both camera fixtures;
Moon terrain and ENet session; practice; arena-selection layout and native
render; airborne replay all pass. Contact network passes at default and 150 ms
profiles; 150 ms launch correction settles in 183.3 ms, lifter in 166.7 ms and
ram in 133.3 ms. The enlarged north/diagonal wall check passes at 80 ms.
The natural duel passes after 16 actual hits through results and active rematch
in 112.5 s with canonical timers. All 25 service tests pass on existing nvm
Node 24.21.0. Native Linux baseline commands replace the PowerShell wrapper.

## Matching release completed

Clean runtime commit `a638a6ef8facfa2eb3a9c025a4eb43bfad7db962` produced
Linux server and Linux/Windows clients. Build `mvp-ab-15`, protocol 6, catalogue
10 hash `623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
All artifact hashes match their records; Linux client starts cleanly under
Vulkan/Forward+ on the RTX 3080. Windows exported but was not executed here.

The actual production container passed private and Quick Play driving, reconnect,
agreed two-round results and active rematch. The same image was deployed by digest
to existing Fly Machine `287e605ad7d578` using the user's confirmed restart break.
No additional Machine was created. Image:
`registry.fly.io/battlebots-fumbleforce@sha256:cbf2f8b87debb586b2e2c94a9977d57c3dda3b15ef37e95a43489e6b7b1c3ff4`
(tag `release-a638a6e-20260923`). Live health and the actual worker build-record
match local artifacts; previous build14 clients receive HTTP409.

External private and Quick Play acceptance both pass with actual reconnect,
results and active rematch. These automated hosted cases resolve rounds by
forfeit; the separate 112.5 s natural-duel fixture supplies combat evidence.
See [container/artifact/live evidence](evidence/foundry-100m-release-2026-09-23.json)
and [external evidence](evidence/foundry-100m-external-duel-2026-09-23.json).
Temporary external logs: `/tmp/battlebots-hosted-51zM7k`.

Matching archives: `battlebots/exports/battlebots-linux-a638a6e.tar.gz` and
`battlebots/exports/battlebots-windows-a638a6e.zip`. Previous release image
`registry.fly.io/battlebots-fumbleforce@sha256:e829cafb8fd0cd96449ab7b59f576dc642d8de49cc9b19b8b1e139af920da8f3`
and its a84fd11 client archives remain available for rollback. The owned local
acceptance container is stopped. Human hosted play/impact feel remains open.
No paths remain reserved after this task is merged.
