# Confirmed combat impact feedback — B implementation

The saved checkpoint was resumed, reviewed with the authored body and validated
after the spark appearance adjustment. Binding tests found and fixed stale effects
after a freed session and cached events during offline/connecting transport states.

Branch `codex/b-impact-feedback`, based on main `6c1eb0e`. Resumed at the user's
request after the pause. B implements GAME_SPEC section 9 sparks and limited
cosmetic metal fragments from confirmed combat events. Maximum 20 fragments and
64 sparks per client, short lifetimes, no collisions, damage or rigid bodies.

Paths: new B presentation renderer and event controller, independent fixtures and
docs. Narrow coordinated menu_game wiring connects the existing session event
signal and match/reset lifecycle. A audio, networking, rules and world code remain
unchanged. No new event fields, protocol/content revisions or prediction effects.

Require current match/round active phase, reject malformed/duplicate/stale events,
clear visuals on reset/phase transitions, retain network replay watermarks across
reconnect and allow fresh practice epochs. Validate these independently alongside
native rendering, caps/expiry and actual game event integration.

## Interfaces and limits

`CombatImpactVisual.spawn_impact(position, normal, kind, damage)` emits world-space
sparks and small metal chips from each of the five weapon families and rams. Zero
damage makes contact sparks without damage fragments. Degenerate normals use an
upward fallback; malformed/nonfinite inputs are rejected. `clear_effects()` hides
all active effects. `spark_count()` and `fragment_count()` expose live counts for
independent acceptance. Pools reuse inactive nodes and replace the oldest particle
at capacity; sparks expire in at most 0.46 seconds, fragments in 1.35 seconds.
Decorative trajectories do not query or change gameplay physics. Meshes cast no
shadows; warm opaque sparks shrink near expiry without a screen flash.

`CombatImpactFeedback.bind_session(session)` owns the event and reset connections.
The normal menu game creates one controller for the whole client. It consumes
existing detached match context and confirmed events, validates kind/IDs/geometry,
rejects duplicate or older IDs per match/round, and clears effects on phase changes.
Network replay watermarks survive reset/reconnect; restarting practice resets its
local event epoch. Match history is bounded to 16 contexts. Presentation cannot
create authoritative damage, alter an event, or infer a hit from animation.

The legacy command-line `mvp_app.gd` console is not wired by this menu-game
increment. A can mount the same controller with `add_child` and `bind_session`;
headless dedicated authority needs no renderer. No audio or protocol change.

## Validation

- Godot 4.7.2 stable baseline passes.
- `combat_impact_feedback_test.tscn` passes: malformed/current/old/duplicate events,
  phase/round changes, reconnect replay, fresh practice epochs and bounded history.
- `combat_impact_visual_test.tscn` passes headless/native: all six kinds, zero damage,
  400-event burst caps and pool reuse, expiry/clear, no collision objects/shapes,
  instance isolation and world-space emission under transformed/moving parents.
- Six native views at six meters show localized sparks, without a fullscreen flash.
- Expanded session-binding checks pass: rebind detaches the old signals, unbind and
  freed sessions clear effects, offline/connecting callbacks cannot respawn them,
  and practice restart starts a fresh epoch.
- `combat_impact_game_test.tscn` passes headless/native with the authored Sawblade:
  actual saw damage and session events produce effects, a replay adds none, expiry
  removes them, and fresh contacts clear immediately on restart/leave. Bot positions
  are controlled/frozen for this contact fixture; it does not certify driving feel.
  The previous in-memory profile draft is restored, without saving it to disk.
- The in-arena six-meter capture shows the authored bot and contact; saw sparks are
  small and partly occluded by the mechanism and caption at this angle. Native
  readability across human gameplay remains an acceptance item.
- Existing gameplay audio regression passes. All three new scenes are registered
  in the presentation runner.

Larger-scene GPU/LOD budgets, human combat readability and remote internet gameplay
acceptance remain separate open gates; these fixture results do not certify them.

## Hammer shockwave, spark showers and nitro feedback (#32)

Follow-up requested by the user on 23 September 2026. It consumes the same
confirmed `combat_event` and the already replicated `BotView.nitro_active`; no
event fields, protocol or catalogue changes. Hit stagger and hammer knockback
(below) are gameplay changes and need a matching hosted server release.

- Every accepted impact also fires one pooled GPU spark shower (up to 240 HDR
  streaks aligned to velocity, at least 60% on light hits; hammer, spinners and saws
  skew denser) plus a 0.14 s contact flash light. At most ten showers, retired
  after 1.2 s.
- Hammer impacts add a shockwave laid on the struck face (a short read-only ray
  through the event contact finds the real surface normal, since event normals
  point from the victim centre): a glowing, screen-
  refracting ring (`impact_shockwave.gdshader`, radius 2.6-4.4 m by damage, 0.5 s)
  and a radial dust front (40 soft puffs). At most four rings, retired after 0.85 s.
  `clear_effects()` hides live GPU particles too, so resets never leave debris.
- `HammerSlamDetector` (per hammer bot, presentation only) spots the strike edge
  (`strike` state, or a fresh cooldown when snapshots skip that tick), places the
  head at the end of the authoritative swing and casts down. A world surface first
  gives `spawn_ground_slam`; a bot first is left to the confirmed combat event.
- Hammer rings call `add_impact_shake(origin, strength)` on the `bot_orbit_cameras`
  group; the local rig attenuates it to zero beyond 14 m x bot scale.
- `NitroFlameVisual` (created by `MvpBot` only with Nitro equipped, non-headless)
  shows blue cone jets, a camera-facing nozzle bloom, world-space embers and one blue
  light while `nitro_active`. Outlets come from the authored models: Scorpion
  `ExhaustLeft/Right` lips, Atlas `Exhaust*Surface` stack rims (vertex top band),
  Sawblade `Horizontal hollow exhaust*` pipe mouths; other bodies vent from the rear
  of the visible model bounds (the model can extend past the physics hull).
  Visibility is judged relative to the bot, so bots spawned hidden keep their pipes.
  Elimination and release extinguish the jets. Nitro drive strength itself is tuned
  in `data/bot_physics.json` (#38), not here.
- Hit stagger (authority): only projectiles and the saw blade stagger. Their
  confirmed hits call `CombatState.stagger(seconds, depth)` from
  `CombatWorld.STAGGER` (saw 0.4 s / 55%, minigun 0.15 s / 30%, plasma and flamer
  0.2 s, tesla 0.3 s, cannon 0.5 s / 65%, railgun 0.55 s / 70%). Hammer, spinners,
  lifter and rams rely on their impulses and never stagger (build `mvp-ab-26`). `stagger_factor()` scales drive, steering and (via
  `DriveBody.grip_multiplier`, 30-100%) tyre grip, easing back over the last 0.3 s.
  Hits extend but never shorten or soften a stagger. It is not replicated; the local
  client's prediction is corrected by snapshots during a stagger.
- Hammer force: blows knock the target away from the attacker and lift it
  (`HAMMER_KNOCKBACK` 2.0, `HAMMER_LIFT` 1.5 m/s before the shared impact multiplier
  and heavy-gravity launch scale) instead of pressing it into the floor.
- Minigun: one pooled pressure ring per accepted shot at the muzzle (0.2 s) and
  barrel smoke driven by presentation heat, strongest after the trigger is released.
- `BotOrbitCamera` eases in a +14 degree FOV kick, 10% boom stretch, a very light
  rumble and neutral white speed lines with a faint dark vignette (CanvasLayer -8,
  below HUD; the blue stays on the vehicle) while the followed bot boosts.
  `speed_effects = false` disables nitro camera effects and impact shake. The rig now
  writes `camera.fov` every physics frame from `base_fov`; a future FOV setting must
  set `rig.base_fov` rather than `camera.fov`.

Validation: `nitro_feedback_test.tscn` (outlets on real Atlas/Sawblade models, flame
state, camera FOV/boom/shake) and the extended `combat_impact_visual_test.tscn` pass
headless. Native Forward+ captures (RTX 4080) were reviewed for the three authored
bodies, hammer ring/dust, saw sparks and the nitro chase camera. Human in-match
readability, a reduced-motion settings toggle and #29 particle-quality scaling of
these emitters remain open.
