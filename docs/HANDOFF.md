# Current A/B handoff

## Garage list model stills and save status — B, 22 September 2026

Garage bot rows now show a captured still of each valid equipped 3D loadout.
One small offscreen renderer reuses captures for unchanged parts and cosmetics;
weapon and paint edits replace the image, and invalid drafts no longer display
unrelated concept art. The main interactive preview is unchanged. Saved File
is now a backgroundless footer link left of Done; amber status appears for
unsaved edits, new builds, and retained copies, and red warns when the file
needs review. Clean builds have no status label. This is client presentation
only: no catalogue, loadout, network, or hosted service compatibility change.
Active B chassis and Nitro sessions also edit PlayerProfile, so this change
keeps save-state presentation in the isolated Garage screen. See
[scope and validation](coordination/B_GARAGE_THUMBNAILS.md).

## Garage catalogue navigation cleanup — B, 22 September 2026

The garage already has the expanded 3D preview, reversed horizontal orbit,
loadout-only side panel, and mass/battery/speed/individual armor values beneath
the bot name. This follow-up removes the remaining Part Catalogue route, screen,
and hidden Customize link, along with screen-only cards. Parts remain selectable
through Customize. The shared menu router no longer accepts `shop`; A should not
restore that route during menu integration. This changes no loadout, catalogue,
network, or hosted compatibility data.

Validation with pinned Godot 4.7.2: baseline, garage catalogue/layout,
customization screens, and Scorpion garage checks pass. Broader presentation
checks still report main-menu synthetic-click/flow failures and composed
small-window bounds failures (`menu_kit_test`, `menu_flow_test`,
`b_menu_text_game_test`); those checks did not pass in this increment.

## Orange Scorpion HX-6 and practice NPCs — B, 20 September 2026

Reference-based Blender source and portable PBR runtime assets now assemble a
hexagonal six-legged orange Scorpion with swappable hammer and minigun. Normal
commands drive physical support/steps, articulated hammer attacks and authoritative
gun fire with elevation tracking, heat/battery and actual world occlusion. Three
authored practice NPCs pilot normal combat commands, break into real module pieces
on confirmed core destruction, and respawn safely for repeated testing. The garage
adds the HX-6 preset and retains existing bodies/builds. Foundry reflections and
4x MSAA improve the metal/material presentation.

The corrected Blender model has a strongly inset roof, six radial leg sockets,
a forged chamfered hammer on a visible telescoping stage, and detailed rotary
barrels/receiver. The diesel follow-up adds a vented engine and two hollow stacks;
bounded world-space soot thickens during real movement and disperses after
stopping. Actual planted tripods play the cropped supplied footfall. The new
hammer recording follows the existing confirmed-hit audio path. See the narrow
[supplied-audio handoff](coordination/B_SCORPION_AUDIO.md).

Current local validation and release status are recorded in
[B Scorpion handoff](coordination/B_SCORPION.md). Catalogue 8 / protocol 5 /
`mvp-ab-13` require A to release matching hosted workers before online acceptance.
No live deployment is claimed by this B increment.

## Supplied combat recordings — 20 September 2026

A adapted the supplied heavy metal collision, hammer crash and continuous saw
recordings to confirmed ram/hammer impacts and powered saw playback. Mono PCM
preparation removes clipping risk from the source peaks, preserves impact tails
and crossfades the saw loop. Effects volume, spatial positions, voice limits and
state guards remain in use. Baseline, recorded-source/loop checks, actual spatial
mix capture and composed audio lifecycle pass. No gameplay/compatibility change
or hosted release. See [mapping and evidence](coordination/A_SAMPLED_COMBAT_AUDIO.md).

## Main-menu cleanup and Practice setup — 20 September 2026

The main menu now has concise aligned navigation, a larger padded bot card and
one name/count/arrow row. A compact preview option retains rotation controls,
keyboard inspection and invalid-build feedback. Practice opens arena setup with
an explicit Start Practice action; arena selection leaves the main menu.
Workshop test drive and default lobby presentation retain their existing flow.
Baseline, menu/practice flow, keyboard/invalid-build checks and native 720p through
ultrawide main layouts at 100–150% text pass. See
[scope and evidence](coordination/A_MAIN_MENU_CLEANUP.md). No gameplay,
catalogue or network changes, and no hosted release is claimed.

## Battle soundtrack — 20 September 2026

A added the supplied Relentless Action MP3 as a looping battle song on the existing
Music bus. It plays through countdown, combat, round breaks and in-game settings;
results, disconnect recovery and leaving stop it. The menu melody remains separate.
Import/baseline, actual loop playback, Music volume preview/cancel, real ENet
results/rematch and reconnect checks pass. No gameplay or compatibility changes;
no hosted release is claimed. See [scope and validation](coordination/A_BATTLE_MUSIC.md).

## Three-times-larger heavy machines — 20 September 2026

B enlarged physical hulls, weapons and drive assemblies by three. Following the
user's torque clarification, strong motors deliver hard acceleration and decisive
turning; inertia, neutral coasting and finite braking give them weight. Drive-package
top speeds and construction budgets remain. Camera, garage framing,
effects, terrain/wall spawn clearance and practice spacing follow the new size.
Known revision-six saves retain their parts and appearance when migrated.

Godot 4.7.2/Jolt checks cover actual geometry/weapon contacts, handling/recovery,
visual framing, saved builds, both arenas and a full natural duel through results
and rematch. An exposed landing-prediction defect was fixed in the static replay
sweep; the 150ms contact gate now passes without relaxed tolerances. See
[scope, measurements and validation](coordination/B_HEAVY_MACHINES.md).

**A release handoff:** catalogue revision 7 hashes to
`45bb581a3c4403fd74ce7067150eb480148e70a6e5b8dba9a5977dda95db25be`.
The live Fly health check still reports build `mvp-ab-12`, protocol 4 and
revision-six hash `63b655000dc8129c3cd52cb735ecfaec5cbc7cdb1513b43de024383e7473e8a5`.
Source integration does not update that service. Prepare matching client/server
artifacts, establish a playtest break before restarting the single Machine, deploy
workers, then run external private/Quick Play duel/results/rematch acceptance.
Compatibility rejection stays enabled; hosted readiness is not claimed here.

## Robot destruction explosion — 20 September 2026

B added confirmed zero-core explosions: rolling fireballs, pressure rings, orange
light, spark streaks, tumbling metal and lingering smoke above scorched wrecks.
Silent existing-wreck baselines, remote state, repair/rematch, camera/collision
preservation and shared twenty-piece debris limits are covered by independent
checks. Baseline and affected regressions pass; native Foundry/Moon captures were
reviewed. No gameplay, networking, audio or catalogue change, and no hosted release
is claimed. See [scope and evidence](coordination/B_DESTRUCTION_EXPLOSION.md).

## Godot Moon atmosphere — 20 September 2026

Follow-up: backdrop geology now receives a separate dim key, and all eight
floodlight housings/lenses tilt toward the arena with matching contained beams.
Moon physics/assets and native scene teardown pass; the original renderer RID
warning remains. See the follow-up in the linked evidence below. The review tool
now captures only production settings to avoid a pinned-engine bug when changing
mesh render layers during a live comparison.

The user returned to Godot. Moon now uses reduced cool ambient/sun illumination,
lower-angle shadows and warm arena floodlights so the mountains recede while the
floor remains readable. Identical 1440p comparisons, rendered two-bot effects,
baseline, lunar physics/assets and ENet reconnect checks pass. The known renderer
texture-RID shutdown warning remains. No gameplay, B paths or Foundry changes.
See [scope and evidence](coordination/A_LUNAR_ATMOSPHERE.md). Unreal and the older
unfinished lunar geometry/material branch remain separate experiments.

## Compact combat HUD — 20 September 2026

A replaced the oversized HUD with an angular illuminated match strip and corner
instruments, segmented resource bars and circular weapon charge. Warnings,
component failures and self-right appear at bottom center. The local floating
YOU tag/leader, compass, alive roster and redundant practice/debug cards leave
the fighting view; world health bars remain. 100–150% text, color palettes,
captions, authoritative state and menu flow
are preserved. Baseline, state/network/lifecycle and native layout checks pass;
healthy HUD cards occupy 7.84% at 720p. See [scope and evidence](coordination/A_HUD_REDESIGN.md).
No combat, input, catalogue or network contract change; human visual acceptance
remains open and no hosted release was deployed for this client-only HUD change.

## Bot visual budget audit — 20 September 2026

Independent geometry/LOD inventory and two/ten-bot native Foundry measurements are
recorded in [the audit](coordination/B_VISUAL_BUDGET.md). The largest of 40 sampled
assemblies has 39,056 triangles; mesh counts and incomplete procedural LODs remain
optimization leads. Resource caps pass; the short RTX 4080 run is not full-game or
low-end performance acceptance. User requested pause after this audit.

## Quick Play service synchronization — 20 September 2026

The existing Fly server now uses main's catalogue revision 6. Its stale catalogue
was rejecting current clients before queueing. Online errors appear above retry
actions and receive focus so the failure explanation remains visible. Build and
protocol gates remain intact; no B implementation changes. See
[deployment and validation](coordination/A_QUICK_PLAY_SERVICE_SYNC.md).

## Confirmed impact feedback — 20 September 2026

The normal menu game now consumes confirmed hit events for localized sparks and
short-lived metal fragments, capped at 64 sparks and 20 fragments per client.
Duplicate/stale events and offline/connecting sessions cannot replay effects;
phase changes, practice restart and leave clear them. No collision or damage is
added. Independent rendering/session/native contact checks pass. Human readability,
larger-scene budgets and legacy CLI mounting remain open. See
[scope and evidence](coordination/B_IMPACT_FEEDBACK.md).

## Player health bars — 20 September 2026 user request

Player world labels now include a fixed-size health bar beneath the text. Green
remaining HP fills from the left, red missing HP fills the right; the full bar
never shrinks. Existing detached core health drives both players' bars. See
[coordinated HUD scope and checks](coordination/B_PLAYER_HEALTH_BARS.md).

## Component damage presentation — 20 September 2026

Weapons and individual drive sides now show snapshot-driven cracked/scorched and
smoking disabled states. Original appearance returns on repair/reset. Authored and
legacy assemblies are covered without physics, health or wire changes. Independent
mapping/state/native runtime checks and baseline pass; follow-distance captures
reviewed. Impact sparks/fragments are covered by the newer increment above; larger-scene budgets and human acceptance remain open.
See [scope and evidence](coordination/B_COMPONENT_DAMAGE.md).

## Garage options — 20 September 2026 user update

Garage/Customize now fill available height before paging. All existing options are
selectable; the sole offered chassis is the authored Sawblade body. Body edits
preserve the other parts and appearance; unsupported-model selection locks and
weapon substitution are removed. Canonical spinners render with the authored body.
Legacy saves retain their IDs/equipment; catalogue revision 6 requires matching
hosted content. See [behavior, migration and validation](coordination/B_GARAGE_OPTIONS.md).

## Camera/input lifecycle acceptance — 20 September 2026

Independent practice/source replacement and real ENet duel scenes verify current
camera anchors/exclusions, camera clearance through round transitions, cancellation
and release-before-rearm. Headless checks and native duel execution pass; baseline
passes. No runtime or shared API change. The prior intermittent baseline shutdown
access violation remains unresolved. See [evidence](coordination/B_CAMERA_ROUND_LIFECYCLE.md).

## Camera mouse scaling — 20 September 2026

The B input adapter now uses unscaled screen mouse motion, so viewport stretching
does not change the selected X/Y orbit sensitivity. Independent engine-transform
and real-adapter tests reproduce the former half/double sensitivity and verify
inversion and menu suppression. Camera settings, input/menu and baseline checks
pass. Existing preference files and shared APIs are unchanged. See
[scope and evidence](coordination/B_CAMERA_MOUSE_SCALE.md).

## Terrain camera clearance — 20 September 2026

An inverted bot could be clear of raised Moon terrain while its camera sphere
remained embedded. The camera now queries supporting ground from chassis height
and raises the pivot only when the candidate sphere and upward path are clear.
Ceilings and walls still constrain the view; no world, drive or BotSource API changes.
Independent lunar poses, ceiling/wall removal, perimeter, existing contact/arena
and settings checks pass, along with Godot 4.7.2 baseline and native visual review.
These are deterministic collision fixtures; human driving feel remains open.
See [reproduction and validation](coordination/B_TERRAIN_CAMERA.md).

## Shared integration baseline

Per the user's instruction, completed task branches merge locally into main
after validation and main is pushed directly. No PRs. Main is the shared latest
combined game; future tasks begin from
updated origin/main. Historical feature-branch names below identify provenance,
not separate places the other developer must collect to obtain finished work.
Any genuinely unfinished remote branch is called out rather than merged blindly.

## Current ownership — user revision

- **A:** menus, networking, game rules, game world and audio.
- **B:** combat, bot assets (models and weapons), bot-customisation menus and
  player controls.

General menu/session/results integration, arena/world and audio move to A.
Combat/weapon mechanics, bot assembly/catalogue and driving move to B. Garage
and bot customisation stay with B. Historical author/owner labels below describe
past work only. AGENTS.md and TEAM_WORKFLOW.md contain the current boundaries.
The natural-duel fixture remains A integration of network and match rules;
demonstrated combat/control defects are handed to B rather than changed by A.

## Current user priority

Updated by the user on 2026-09-20: finish a fully working 1v1 game first. External
matchmaker/dedicated-server deployment is now live on Fly with automated public
duel acceptance; two-computer human hosted acceptance remains open. HUD work is
raised in priority. Deliver the full hosted duel loop through combat, rounds, results
and rematch. Defer 2v2, FFA and all other multiplayer modes until the 1v1 game is
fully working. The tutorial is also deferred until then, with B retaining control
exercise ownership and A retaining menu integration.

Further user feedback (2026-09-20): menus still need refinement, particularly
the multiplayer/networking screens that fit poorly into the original menu
system. A owns this high-priority 1v1 work alongside hosting and HUD: consistent
visual design, layout and navigation across online entry, host/join, connection
progress, errors/retry/cancel and lobby transitions. Validate the complete
rendered player flow; this board entry does not claim the menus are fixed.

The user also requests win and score screens and an in-game menu page consistent
with the other panels (2026-09-20). These are high-priority A-owned 1v1 delivery
tasks. Existing results/rematch implementation is a foundation; its historical
completion does not close these requested presentation tasks. Use authoritative
outcomes/scores and review navigation through game menu, win, score and rematch.
The current board retains an explicit open presentation-refinement task across
these pages and networking menus. Implemented menu-panel checkboxes record the
existing foundation, not closure of the user's remaining design feedback.

The user reports human multiplayer was conducted successfully through a tunnel.
Record that gate as completed human-play evidence; do not keep describing human
multiplayer as untested. No specific measurements were supplied, and this does
not establish external-hosting reachability or release acceptance. Older human
LAN/playtest and 1v1/2v2 priority statements below are historical and superseded.
Existing modes/tests remain; larger-mode expansion, optimization and soak work
do not block the active 1v1 scope.

## Current Developer B increment

B's direct TEST DRIVE entry now opens real practice from Garage/Customize with
the unsaved build and selected arena. BACK TO BUILD restores the originating
screen without saving, reloading or losing edit history. Independent entry/game
scenes cover validation, hidden shortcuts, settings, restart and session guards;
native layouts and affected regressions pass. See
[test-drive handoff](coordination/B_GARAGE_TEST_DRIVE.md). The separate active
Sawblade/physical-legs task retains model, registry, drive and Customize source
ownership; this increment avoids those files.

B's featured vehicle increment replaces the main static image and lobby dropdown
with shared selection and an isolated rotating chassis/weapon preview. Lobby
selection remains a draft until Apply is host-confirmed; paint-only confirmation
and phase/pending locks are covered independently. See
[featured vehicle handoff](coordination/B_FEATURED_VEHICLE.md). Its shared preview
now also assembles Sawblade Tank's selected authored modules and walking legs.

Sawblade Tank integration adds the authored runtime model, all root module and
paint controls, primary-driven hammer clip and physical walking-leg drive.
Catalogue revision 5 requires matching clients/server; the live hosted worker
has not been deployed by this B task. See
[the Sawblade handoff](coordination/B_SAWBLADE_INTEGRATION.md) for exact mappings,
automated climbing/network evidence and remaining human playtest scope.

B's latest menu accessibility work is documented in
[the B handoff](DEVELOPER_B_HANDOFF.md#b-menu-text-accessibility--20-september-2026).
Garage/Customize/catalogue/recovery and camera/input settings consume the shared
100/125/150% text preference with wrapping and keyboard-accessible pages instead
of scrolling, incorporating the newer user feedback from A's fe9f2f0. Documented
menu_game integration propagates text scale and leaves physical window layout to
B's responsive settings panel; stable APIs integrate with A's hub. Independent
scenes, composed preference preview/save/cancel,
rendered 720p layouts, baseline and affected regressions pass. See
[text evidence](coordination/B_MENU_TEXT_ACCESSIBILITY.md).

## Current Developer A increment

`codex/a-live-duel-refinement` now addresses the user's manual hosted menu
feedback: oversized scrolling navigation, unused screen margins, competing
yellow actions, hidden private code and inconsistent settings. Full presentation
and network-flow checks pass. Integration includes B's published live garage
preview, part comparisons and saved-build repair through `e24ab02`; the shared
baseline and ten affected garage/profile/menu/settings checks pass after rebase.
All requested items, including B's vehicle selection and rotating 3D showcase,
are tracked in [the menu feedback handoff](coordination/A_PLAYTEST_MENU_FEEDBACK.md).
A owns the settings hub/video integration; B retains controls/camera behavior.
Public private/Quick Play reconnect already passed against the unchanged Fly
worker, retaining identity and idle state with token rotation. See
[recovery evidence](coordination/A_LIVE_DUEL_REFINEMENT.md).

### Preceding live deployment increment

`codex/a-fly-duel-live` follows `2b42812`. The user approved hosting costs; one
Stockholm Machine now serves `https://battlebots-fumbleforce.fly.dev`. Both
private and queued duels passed actual public UDP gameplay, results and rematch.
Current clients use that endpoint. A measured packet-size black hole on the Fly
route and enabled symmetric ENet range-coder compression, requiring matching
`mvp-ab-12` clients/server. Protocol 4 and B bot records remain unchanged.
The packet-limit regression also covers reconnect/results/rematch. See
[live deployment](coordination/A_FLY_DUEL_LIVE.md). Human hosted acceptance and
the previously observed Windows native shutdown issue remain open.

### Preceding Quick Play increment

`codex/a-duel-quick-play` follows `5015c7e`. Quick Play explicitly queues two
players, with isolated legacy four-player support and advertised capability.
The original-theme panel offers Quick Play alongside private create/code join.
Expired online credentials clear stale membership so a new explicit action can
retry. The hosted harness exercises both private and queued duels through
results/rematch. B source and Godot wire contracts remain unchanged; see
[duel queue evidence](coordination/A_DUEL_QUICK_PLAY.md). External deployment is
now live; human design acceptance and the intermittent native shutdown crash remain open.

### Preceding impact/crowd audio increment

`codex/a-impact-crowd-audio` follows `0023ad9`. A spatializes the four impact
voices using accepted event world positions and adds one bounded crowd voice
for real round/match outcomes. Initial/rejoined/practice state stays quiet;
new rounds and leave clear previous reactions. Captured engine output verifies
left/right panning and distance attenuation. No B source or wire changes;
see [impact/crowd evidence](coordination/A_IMPACT_CROWD_AUDIO.md).

A also repairs the separate online-menu HTTP fixture bind failure with an
OS-assigned loopback endpoint and explicit failure diagnostics. See
[fixture evidence](coordination/A_ONLINE_FIXTURE_PORT.md). The latest observed
Windows run35504840930 at0023ad9 still fails with native0xC0000005 after DRIVE
PASS; neither the audio work nor fixture repair claims to resolve that issue.

### Preceding combat-status audio increment

`codex/a-combat-status-audio` follows `fb3d633`. A adds weapon status and armor
breach cues with captions from accepted local views; precise wording avoids
duplicating B's attack eligibility rules. Fresh baselines are silent, invalid
or stale views do not fabricate events, and critical captions retain concurrent
core/recovery/armor details. Three fixed announcement voices preserve those
simultaneous sounds. The caption layout fits enlarged text alongside existing
HUD and network panels. B producers, combat, input and assets are unchanged;
see [status-audio evidence](coordination/A_COMBAT_STATUS_AUDIO.md).

### Preceding continuous-audio increment

`codex/a-spatial-gameplay-audio` follows `9a3053a`. A adds a detached session
audio accessor over existing physical snapshots and first-pass 1v1/practice
drive/sliding/spinner/saw/arena loops. Client audio uses accepted authority data
even for the predicted local bot; spatial positions follow presentation. Two
fixed bot rigs cap voices, stale data and menus/recovery stop playback, and
warnings duck ambience without changing saved bus volumes. B's producers,
controls, camera and assets are unchanged; no wire change. See
[audio evidence](coordination/A_SPATIAL_GAMEPLAY_AUDIO.md). Remaining cue coverage,
spatial impact mixing and human listening acceptance stay open on the board.

### Preceding world-marker increment

`codex/a-duel-world-markers` follows `fa99d97`. A's read-only 1v1/practice world
badges use symbols plus YOU/RIVAL/TARGET/OUT text and the saved HUD accessibility
settings. Published presentation poses keep them attached to the displayed bots;
depth-tested stems clarify which bot a label belongs to. Menus/recovery suppress
them, and missing baseline/invalid views cannot fabricate identities. No B bot,
paint, camera or controls implementation changes. See
[world-marker evidence](coordination/A_DUEL_WORLD_MARKERS.md). Human acceptance
and other open board items remain separate.

### Preceding general-menu text increment

`codex/a-menu-text-accessibility` follows `35ef6a6`. The saved text preference
now applies to A's general menus and game/results/reconnect/audio/accessibility
panels as well as the HUD. Original-theme layouts wrap and scroll while keeping
actions keyboard reachable. The shared local helper is documented in CONTRACTS;
B's garage/customisation/control settings remain a separate owned follow-up.
See [menu accessibility evidence](coordination/A_MENU_TEXT_ACCESSIBILITY.md).
No B runtime, gameplay rules or network schemas changed.

### Preceding Windows diagnostic increment

`codex/a-shutdown-diagnostics` follows `7287540`. Bounded Windows experiments
reproduce the native shutdown failure after successful gameplay assertions.
Removing WireCodec's concrete bot type did not fix it and was reverted. A's
drive gate now rejects native crash text even with exit zero, and a repeatable
diagnostic runner retains every trial instead of retrying toward a green result.
No B implementation or game behavior changes. See
[diagnostic evidence](coordination/A_SHUTDOWN_DIAGNOSTICS.md). The crash remains
open; this increment improves detection and reproduction, not runtime stability.

### Preceding Linux runtime increment

`codex/a-linux-hosted-runtime` follows `4cf0a99`. A new independent Linux job
builds and starts the production Docker image as its default unprivileged user,
then runs two host-side clients through its real allocated UDP release server,
results and rematch. Linux run35501573901 at8686c24 passes with inspected artifacts.
Windows run35501573844 on the same source failed after DRIVE PASS with the known
native0xC0000005 shutdown issue; full Windows CI is not claimed green. No B runtime
was changed and no failure gate was relaxed. See [runtime evidence](coordination/A_LINUX_HOSTED_RUNTIME.md).
External Fly routing/human play and hosting-cost confirmation remain outstanding.

### Preceding HUD accessibility increment

`codex/a-hud-accessibility` follows `bd1dd3f`. General Settings now offers HUD
text at 100/125/150%, four color palettes and opaque high-contrast panels with a
visible sample, save and cancel. Combat/round HUD fonts enlarge independently
from viewport scaling; larger panels reflow. Practice readout and announcement
captions follow the selected size. B implementation and wire format are unchanged.
See [accessibility evidence](coordination/A_HUD_ACCESSIBILITY.md). Whole-menu text
scaling, world/team markers, pings and human accessibility acceptance remain open.
Hosting remains unprovisioned pending the recurring-cost decision.

### Preceding reconnect increment

`codex/a-reconnect-flow` follows `50f3a63`. The general game now offers manual
same-session recovery after unexpected transport loss, with bounded status,
retry/leave and original-menu styling. It retains hosted membership, restores
the damaged bot or result screen from the authoritative baseline, and clears
private credentials on leave/rejection/expiry. A local session API addition is
documented in CONTRACTS.md; no B implementation or wire schema changes.
Independent network, composed-game, rendered panel and existing regressions pass;
see [reconnect evidence](coordination/A_RECONNECT_FLOW.md). Rebuild deployment
artifacts from updated main before external provisioning. Billable hosting still
awaits confirmation and no external reachability is claimed.

### Preceding hosted acceptance increment

`codex/a-hosted-duel-deployment` prepares external 1v1 acceptance after `bca152c`.
The hosted harness can target an HTTPS allocator without starting a local server,
and verifies assigned ENet play through two forfeit-driven rounds, agreed scores,
results and an active rematch. Fresh Linux and Windows exports, service checks
and Fly configuration validation pass. External hosting remains unprovisioned;
the existing pending confirmation concerns the recurring one-Machine/dedicated-IP
cost. See [deployment acceptance](coordination/A_HOSTED_DUEL_DEPLOYMENT.md).
Do not treat a local test or a Linux export as proof of external reachability.

### Preceding HUD increment

`codex/a-duel-hud` follows menu panels `1a5d38a`. The default game now has a
read-only combat HUD for resources, raw component integrity/breaches/disables,
weapon state/charge/cooldown, recovery availability/cooldown, prominent
immobilization/elimination/core/heat warnings, chassis heading and duel bot status.
Round countdown/time/score/outcome use the original menu theme and scale through
4K. Combat, practice, diagnostics and captions share the HUD layout; menus and
settings suppress it. The preview's old resource/hint overlays remain for its
standalone fixtures, while the default game uses the composed HUD.

`MvpSession.bot_views()` is a local read-only API with fresh detached records;
clients omit bots without an accepted snapshot. It prevents missing baselines
from masquerading as healthy bots. No B combat/control/bot implementation or
wire/schema changed. See [HUD evidence](coordination/A_DUEL_HUD.md) for validation
and limitations. External hosting remains outstanding. Text-scale/color-vision
presets and coordinated ping presentation are still open, not part of this core
HUD delivery. The known intermittent engine shutdown issue also remains open.

### Preceding menu-panel increment

`codex/a-duel-menu-panels` implements the requested general menu refinement from
`1a56c38`. Online entry now focuses on private 1v1 create/join with original menu
art/theme, service status and cancellation. Direct host/join uses labelled,
centered connection panels and the connected lobby retains the roster/build flow.
Win overview and score-detail tabs read authoritative records; local BotView team
determines victory/defeat. The in-game menu shares the original panel styling,
preserves resume/settings/restart/leave actions and prevents HUD overlap.

Baseline and all four new independent panel checks pass, with rendered 720p and
1080p review. Real HTTP/ENet private-duel cancellation/join/leave and two-peer
round/results/rematch pass; the latter asserts local defeat and score navigation.
Practice, audio, menu flow/music and existing results checks also pass. Review
caught and fixed a diagnostics button-down visibility regression, now tested.
Some checks still report the known two-object shutdown warning; no native crash
occurred in these runs and the historical intermittent engine issue stays open.
See [full evidence](coordination/A_DUEL_MENU_PANELS.md). External deployment and
HUD expansion remain outstanding; this increment does not provision hosting.

### Preceding Foundry increment

`codex/a-foundry-arena` follows practice `c83d266` with the user-requested regular
octagonal Foundry (50 m across faces), eight cage/gallery bays, radial trusses,
worn steel materials and an octagonal lighting crown with warm/cool spots and
volumetric haze. Spawn transforms are unchanged. The existing camera scene gets
the matching corner boundary setting; no camera/input algorithm changes.
Build `mvp-ab-11` prevents older square-arena peers from joining. Protocol and
catalogue stay at 4. See [arena evidence](coordination/A_FOUNDRY_ARENA.md).

Baseline, headless arena/spawn-clearance, camera containment, rendered review,
80 ms actual-ENet straight/diagonal wall contacts, and the integrated practice
reset check pass. Rendered screenshots are in the arena worktree's ignored
`battlebots/exports/arena-review/`. These use primitive runtime bots; bot art
remains B-owned. Human review and lower-end graphics performance remain open.
Audio/practice are retained. Completed ownership clarification `86abe77` is also
integrated; the other A session removed its unfinished tutorial rather than
publishing control-training work.

### Preceding practice increment

`codex/a-practice-loop` adds practice-only Restart, a read-only target damage and
knockout panel, and automatic pause/focus on player knockout. Both bots are
repaired/repositioned in the same world with their loadouts retained; queued
actions are cleared. Network sessions reject the reset API unchanged. Baseline,
independent HUD/session/menu tests and real two-peer round/results/rematch passed.
A real post-reset hammer hit confirms the repaired target remains playable.
The network test reported four ObjectDB instances at shutdown; the known cleanup
issue remains open. See [practice evidence](coordination/A_PRACTICE_LOOP.md).
The following arena increment now includes this completed practice work.

`codex/a-gameplay-audio` adds A-owned first-pass impact, round, warning and recovery
cues with captions, plus saved volume/mute settings. The menu composes Audio
alongside existing control settings and routes the supplied melody through its
own music bus. B combat, controls, assets and customisation remain unchanged.
Focused audio/controller/settings/menu checks, the baseline and the real-time
two-peer results/rematch check with cue assertions passed; see
[audio evidence and limitations](coordination/A_GAMEPLAY_AUDIO.md). This is
procedural first-pass sound, with spatial mixing and listening polish still open.
The existing playtest ZIP below predates this increment.

`codex/a-duel-combat-loop` adds an independent two-player natural-combat check
and applies the user's revised ownership throughout the active docs. The final
check passed at 93.5 seconds: sixteen real hammer hits, two core-destruction
round wins, synchronized results and a fully repaired active rematch. Canonical
commands/physics/rules remain unchanged; no forfeit or injected health/charge.
No ten-player work is included. See [duel evidence](coordination/A_DUEL_COMBAT_LOOP.md).

CI 35470427285 reproduced native exit 0xC0000005 after DRIVE PASS. This extends
the known shutdown evidence below; it is not a passing drive validation run.
No retries or relaxed failure detection are used to declare that issue fixed.
Hosted CI 35470075437 subsequently passed its complete suite/export checks;
that successful run does not resolve the intermittent native shutdown failure.

Fresh Windows gameplay package from source `8433dc0`:
`battlebots/exports/playtest/battlebots-gameplay-8433dc0.zip` (129,573,157 bytes),
SHA256 `CECFF8AAD19C33D5BFAAE9330434943A18408E1598F8D82B5EA7214820F9865C`.
Contains executable, matching PCK and short Practice/LAN/control instructions.
Includes B results/rematch and the supplied menu melody. The old menu/music ZIP
is preserved. Exported menu startup/exit and dedicated server plus two independent
clients reaching active passed. Menu shutdown reported the known two-object
warning; no native crash occurred in that run. Human combat feel and internet
play are not certified. The endpoint remains empty pending deployment, so this
package offers Practice and LAN, not a working public service.

`codex/a-results-integration` combines hosted `2eefc31` with B results `cc49a15`.
The shared menu retains online cancellation/error routing and now presents B's
authoritative final/per-round results, FFA placements and rematch controls.
Baseline, detached results, actual online lobby and full two-peer match/rematch
checks passed. The results fixture is registered in the presentation runner.
See [integration evidence](coordination/A_RESULTS_INTEGRATION.md). B's existing
two-object test shutdown warning did not reproduce in one verbose diagnostic
run and remains unresolved; the native engine
shutdown limitation below remains open. Fly deployment is awaiting the user's
confirmation of the concrete billable resources, not a technical deployment claim.

### Preceding hosted increment

`codex/a-hosted-matchmaking` follows performance `3f0e80f`. The user's new priority
is externally hosted matchmaking/gameplay without tunnelling, using Fly.io or
Cloudflare. Fly.io supports the existing native Godot/UDP server; the chosen
first deployment combines HTTPS guest/room/queue service and a bounded dedicated
server pool on one Stockholm Machine. Build `mvp-ab-10`, protocol 4, catalogue four.
See [hosted coordination](coordination/A_HOSTED_MATCHMAKING.md) and
[deployment](../services/matchmaking/DEPLOYMENT.md).

Implemented flow: Play Online → Quick Play (2v2), Create private game, or Join by
code → assigned ENet server → existing lobby/Ready. Only actual server welcome
advances the menu. Guest credentials stay in memory; expiry, cancellation and
server errors are explicit. Admission binds build, identity, slot and reservation
generation; reconnect retains damage while revoked reservations lose access.
LAN and practice remain available. Source-level HTTP plus independent Godot
processes passed both private two-player and queued four-player active gameplay.
Nineteen Node checks, pure/real-ENet admission, service-client cancellation/errors,
online menu-to-ENet lobby, existing LAN duel/rematch and snapshot recovery passed.
The same private/queue check passed with a released Windows server executable;
Linux server artifacts and Fly configuration are prepared. Exported workers use
normal application startup because templates ignore the editor's script override.
No public app/IP/Machine has been provisioned. Linux runtime and real external
UDP reachability still require deployment; the default service URL remains empty.

Performance CI 35468529835 passed all A checks and the repaired catalogue check.
It failed after CAMERA CONTACT PASS with native exit code 0xC0000005. Local
baseline validation also intermittently crashes after BASELINE PASS, despite an
earlier successful run. Diagnostics map the native fault to GDScript language
shutdown; scene nodes were already freed and extra teardown frames did not fix
it. Some crashes print a native backtrace but return zero, so test gates now reject
native crash signatures as well as script errors and nonzero exits. This remains
an unresolved engine shutdown limitation, not a passing baseline or a proven
gameplay fault. No speculative production workaround or gate relaxation was made.

The full public-release service scope remains open: durable accounts/results,
parties, region/skill matching, multi-Machine allocation and release acceptance.
The earlier performance increment's 300-second run reached 59.996 Hz, all five
weapons, one completed match and rematch. Its average downstream was under budget,
but ten-second peaks reached about 114 KB/s. Those ten-player optimization and
soak targets are now outside active scope per the user's priority correction.

### Preceding performance and weapons increment

`codex/a-performance` follows saw `5d3fd30`, hammer `9610946`, horizontal spinner `b46084e` and menu/music
export `db87257`. All five weapon families now have authoritative mechanics and
primitive visuals. The saw cuts for 6 raw per third-second of maintained contact;
breaking contact or power clears the partial interval. See
[saw coordination](coordination/A_SAW.md), [hammer](coordination/A_HAMMER.md) and
[horizontal spinner](coordination/A_HORIZONTAL_SPINNER.md) for independent evidence.
This branch uses build `mvp-ab-9`/protocol 4 with catalogue revision four; both peers
must update together. Known revision-one/two/three saves migrate without changing
parts. The `db87257` playtest ZIP is preserved separately.

Menu/music CI 35465682771 passed. Horizontal CI 35466215676 failed an FFA exact-health
observer check; hammer CI 35466883297 failed two observer spawn comparisons after
a ten-player rematch. Both bounded local reproductions passed. Failure-only
diagnostics were added without weakening either gate; the causes remain unproven.
Neither run is described as full acceptance. Performance/soak, public services
and manual LAN/internet/contact-feel remain open A work.

Saw CI 35467391486 subsequently passed every A MVP check, including FFA and 5v5
profiles. It stopped in B's catalogue fixture, which still expected fourteen
parts after the catalogue grew to seventeen. This increment updates only that
assertion to verify the registry and each part, including all five weapons;
the targeted presentation test passes. Production B UI and assets are untouched.

The current increment adds reliable bot-state checkpoints on match transitions
and during the existing one-second active/countdown heartbeat. A new actual-ENet
regression reproduces and repairs stale health/epoch after a round reset when
unreliable snapshots are entirely lost. Delayed checkpoints cannot rewind newer
snapshots. This is a proven defect, not a confirmed cause of the earlier CI
failures. Baseline, combat physics, detailed-results bounds, profile-zero 5v5 and
the recovery scene pass. Contact regressions at 80/150 ms both pass with worst
settling 183.3 ms against the unchanged 250 ms gate.

The eleven-process performance harness uses normal five-weapon 5v5 matches,
measures UDP bytes with overhead and OS process memory, and distinguishes smoke
evidence from the required sixty-minute soak. Combat events now expose canonical
weapon IDs or `ram` in `kind`. See [performance coordination](coordination/A_PERFORMANCE.md)
for measurements and limits: callback timing excludes the engine's Jolt step,
and headless runs cannot certify rendered frame-time budgets.

## Current playtest checkpoint

`codex/a-menu-flow` follows `d417d7e` with the user-requested menu-flow correction.
Main has Host Game, Join Game, Practice and Garage. Joining goes directly to an
endpoint and accepts the host's mode; hosting chooses mode then lobby. Mandatory
garage/map steps are removed; all four modes share the polished lobby with an
optional saved-build selector. FFA uses individual HUD outcomes and all large-mode
players appear in loading/roster views. See [menu correction](coordination/A_MENU_FLOW.md).
The user requested an updated export, then resumption of A's remaining spec work.

### Earlier combined checkpoint

`codex/a-b-playtest` combines A FFA `b71cb9b`, B menu kit `595c8f9` (including
controls, diagnostics, lobby and match HUD), results intent `0f343f7`, Flamebot
`909b666` and sawblade source `5e163af`. Build is `mvp-ab-5`, protocol 4.
F5 opens the supplied menus; advanced modes use the explicit 5v5/FFA setup route.
See [integration record](coordination/A_PLAYTEST_INTEGRATION.md) for validation.
This was the wind-down checkpoint; remaining game scope stays open. It does not
claim release acceptance. Current menu navigation is described above.
Local Windows and Linux exports are under `battlebots/exports/playtest/` (ignored
build output). The Windows ZIP contains the executable, its required adjacent
PCK and build/testing notes. The separate modelling checkout remains untouched.

## Integration checkpoint

`codex/a-b-integration` at `bdb42ef` is the playable combined checkpoint. Its CI
passed: full MVP checks, Windows/Linux exports, and independent process startup.
It includes B's published arena/camera/HUD/settings at `40aa6b1`, A's simulation,
networking, simple app menus and primitive weapon placeholders. Main has not been
updated. That checkpoint uses `mvp-ab-2`/protocol 3. The A follow-up described below
uses `mvp-ab-5`/protocol 4; both PCs must use the same branch/build. The preceding
transport branch remains `mvp-ab-3`/protocol 4 and has passed CI.

Host chooses 2 players (1v1, app default), 4 players (2v2), or 10 players (5v5
on the current branch), or FFA with a 4–8-player maximum. FFA needs at least four
connected/ready players; team modes need the full count. One window per person;
all players must Ready. Session actions are conditional on connection/match phase.
Escape toggles the app menu; explicit Main menu safely leaves. Independent tests
cover round-end Escape, full matches/rematches, reconnect and malformed input.

## Active A work

A's FFA implementation is on `codex/a-ffa`, based on tested 5v5 `e118f91` and transport fix `df509a0`
(which builds on contact `7235e50` and integration `bdb42ef`). Reserved paths:
`scripts/networking/`, relevant `scripts/simulation/` prediction code,
`tests/network/`, A check scripts, and these shared coordination docs.
Current FFA work includes match rules, spawn selection, independent simulation
tests and A's app host selector. See [FFA coordination](coordination/A_FFA.md).

Independent network scenes now measure a launch/flip, actual lifter and spinner
hits, head-on ramming, recovery and round resets at 0/80/150 ms. At 80 ms, these
scripted cases settle within 250 ms. Settled means the
local presentation remains within 0.25 m and 10 degrees of the simultaneous
server pose for the rest of the observation window (at least 500 ms after each
weapon/ram hit). These are repeatable headless cases, not proof of all contact
conditions. Human camera/contact feel and two-computer LAN remain unverified.

First measured fix: airborne command replay now integrates gravity and full
roll/pitch/yaw, using the body's angular damping and the same velocity caps.
`tests/network/airborne_replay.tscn` compares 250 ms of replay with a real Jolt
body after a launch/spin. Before the fix, maximum errors were 0.327 m, 2.45 m/s
and 75.99 degrees; after, below 0.001 m, 0.001 m/s and 0.04 degrees. This isolated
free-flight check is part of `tools/check-mvp.ps1`.

The delayed-network test then exposed over-replay of authoritative impulses and
a visual offset applied before its physical correction. Replay now uses an
estimated server clock, separately from the pending input backlog; offsets apply
when Jolt consumes the correction. Visual offsets above 0.25 m decay faster than
small driving corrections: a 150 ms lifter trace had already converged physically
but missed the visual settling target at 283 ms with the old blend rate.
Active reconnect baselines restore velocity
and angular velocity too. Snapshot epochs include round number, old-round packets
are rejected, and reset interpolation history is cleared. Baselines produced
before Jolt applies a pending reset encode the spawn with zero prior-round motion.
No B-facing API changed;
private messages require the new build/protocol. See [contracts](CONTRACTS.md).

Regression scenes: `tests/network/contact_reconciliation.tscn` and
`tests/network/clock_sync.tscn`. The clock scene checks real staggered join/reconnect
origins, synthetic symmetric RTT samples, bounded replay and airborne baselines.
Synthetic RTT samples do not emulate the reliable control transport. The existing
profiles impair unreliable input/snapshot traffic only. Full MVP suite also covers
round navigation/rematch and four-client sessions; non-contact correction p95 at
80 ms was 0.125 m in the final real-time run. Whole-control-transport and wall
coverage are added by the current follow-up below; manual LAN and a broader
collision matrix remain acceptance work.

Validation: final `tools/check-mvp.ps1` passed with Godot 4.7.2/Jolt, including all
three real-time network profiles and the independent clock/reset scenes.
Worst scripted settling was 183.3 ms at 80 ms and 250 ms at 150 ms. The independent
dedicated-server/four-client process check also passed. This follow-up is ready
for integration; its CI run 35459583307 passed validation, exports and process
checks, separately from the older checkpoint above.

Network checks now cap execution to real-time 60 FPS while preserving 60 Hz fixed
physics. Accelerated fixed-120 testing produced an ENet packet throttle drop from
32 to 1 and lost a recovery press before server validation (8 accepted commands/s).
The real-time 120-render/60-physics check delivered it once at 60–62 commands/s and
passed. Do not retry away that failure or interpret accelerated transport loss as
the configured impairment profile. Pure physics checks may still run accelerated.

### Completed transport follow-up

See [the current acceptance record](coordination/A_TRANSPORT_ACCEPTANCE.md).
New independent scenes cover opaque whole-UDP impairment, a four-client full
match/reconnect/rematch through that relay, sustained north-wall/chamfer contacts,
and phase-aware remote extrapolation. The relay drops the initial connect packet
deliberately to exercise ENet retransmission; actual RTT is measured separately
from configured delay. Wall replay previously crossed the north wall; static
geometry sweeps reduced the targeted peak error from 1.060 m to 0.014 m. A second
reproduced defect extrapolated stale falling remote poses below the floor during
countdown; extrapolation is now limited to active/overtime surviving bots.
These fixes preserve public APIs, protocol 4 and build mvp-ab-3. No B/model files
are changed. Final `tools/check-mvp.ps1` passed, including all three whole-UDP
profiles and existing contact/session checks. The separate dedicated server plus
four client processes also reached active without errors. Current contact worst
settling was 183.3 ms at 80 ms and 216.7 ms at 150 ms; 80 ms non-contact correction
p95 was 0.137 m. Whole-UDP measured RTT samples were 119–151 ms with an 80 ms
injection and 185–219 ms with 150 ms, with clock error at most 0.5 physics ticks.
These are local automated results; two-computer LAN and human feel remain open.
CI run 35460811964 passed the complete transport increment, both exports and
independent-process checks.

### Completed local 5v5 follow-up

Ten-slot custom lobbies use five existing Foundry markers per side, 240-second
rounds and the same judging, first-to-two, overtime and five-round cap. The host
menu and `--players=10` select the mode; every slot must connect and Ready. The
new build ID rejects older clients. Result payloads now accommodate all ten
players and five rounds, while frequent timer messages contain compact summaries.
Detailed stats remain in the results event and are restored on reconnect.
Reordered entity snapshots also no longer discard each other's valid updates:
the transport is unordered, with stale/duplicate rejection by per-entity tick.
An actual-ENet adversarial scene failed with the old annotation and passes after
the fix, including stale and duplicate packet rejection.
The final full MVP suite passed, including independent rule/spawn, full-results
delivery, adversarial snapshot ordering and ten-client sessions at 0/80/150 ms
injection. Separate server-plus-ten-client and server-plus-four-client process
checks passed. Evidence: `%TEMP%/battlebots-five-mvp-final.log` and the linked
coordination record. This is not yet a ten-player combat performance certification.
Its CI run 35462495199 failed the older network presentation movement fixture:
that ENet integration scene was still accelerated with `--fixed-fps`. The FFA
follow-up runs all ENet integration scenes in real time and measures driving by
physics frames, preserving the movement threshold. Its new CI must verify this.

### Current FFA follow-up

FFA now has 4–8-slot custom lobbies, unique hostile bot identities, existing FFA
arena spawns, one 300-second round, individual forfeits and all-survivor spectator
candidates. Elimination ticks determine placement, simultaneous eliminations
share place, and complete first-place ties share the win. Timeout survivors rank
by rounded core percentage then effective damage. The A app exposes mode/capacity
and placement results. B should use the new winners/placements fields documented
in CONTRACTS.md, retaining team result semantics for team modes.
Independent rule/menu tests and FFA sessions at 0/80/150 ms pass. Reservation
expiry, results reconnect and reduced-roster rematches pass separately. The first
full run found a 5v5 unreliable-clock starvation case; bounded clock exchange now
uses reliable control. Combined integration testing subsequently exposed reliable
reply asymmetry after reconnect; a bounded minimum-RTT clock filter fixes it, with
the 150 ms transport reconnect gate passing at 0.5 ticks. The integration record
distinguishes the failed full run from focused reruns. No performance or human
LAN acceptance is claimed.

## Other developer / modelling boundary

The user authorized merging published B/art work for this testing checkpoint.
Flamebot `909b666` and sawblade `5e163af` are included as assets/source; no combat
geometry or stats were changed. The separate modelling worktree at
`C:/Users/jorge/battlebots-art-flame` remains untouched. Saw source is excluded
from Godot import until a portable runtime export exists.
B controls, diagnostics, match HUD and menu kit are merged. Small integration
changes add the advanced-mode route and guard, consume rebound control labels,
and return to the configured main menu. SessionBotSource's input gate remains.
Both developers' contract/TODO additions are preserved. The historical
`codex/b-match-results` intent was superseded by the merged results follow-up;
current win/score presentation is described in the latest increment above.

## Remaining delivery scope

See [A MVP acceptance](A_MVP_TASKS.md) and the phase assignments in
[TEAM_WORKFLOW.md](TEAM_WORKFLOW.md), subject to the current priority above.
A still owns playable small-match network/contact acceptance,
public services and verified persistence. These are not complete just because
MVP automated tests pass. B owns combat, bots, garage/customisation and player
controls; A owns general menus, world and audio under the revised division.

Earlier measurements and incremental handoffs are retained in
[the dated archive](archive/A_HANDOFF_2026-09-19.md); that archive is historical.

## A — Lunar Outpost arena, 20 September 2026

`codex/a-moon-arena` adds an octagonal Moon battlefield with sculpted terrain,
regolith shading, pebbles, low-gravity dust, floodlights/shadows, outposts and Earth.
Main menu ARENA selects Moon for practice and LAN hosting; online follows the
server, with deployed hosting still Foundry. Moon changes physical terrain and bot
gravity to 1.62 m/s². Existing body gravity-scale/replay support is consumed without
B implementation edits. Baseline arena selection and capability negotiation keep
older Foundry hosting compatible. See [implementation and validation](coordination/A_MOON_ARENA.md).
Human lunar handling/balance and low-end performance remain playtest work.

## A — Cinematic lunar environment

Custom Blender rock/outpost assets, layered original materials, baked outpost
indirect lighting, reflections, localized animated volumetric dust, vent/beacon
choreography, layered movement dust and pooled fading tracks are implemented.
The collision/gravity/network contract stays unchanged. See
[cinematic Moon evidence](coordination/A_LUNAR_CINEMATIC.md) for 1440p performance,
validation, source rebuild steps and the pinned renderer shutdown warning.
