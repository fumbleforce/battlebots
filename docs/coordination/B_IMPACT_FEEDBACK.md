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
