# A natural duel gameplay check

Owner: A. Branch `codex/a-duel-combat-loop`, based on playtest handoff `ef798ba`.
User priority is playable small matches; no ten-player work is included.

Verify the existing gap between isolated weapon tests and the menu's forfeit-based
round test: canonical bots must approach using real commands, cause real weapon
damage and finish a normal duel through authoritative rules, then rematch.
Do not teleport combatants into hits, set health/charge, call damage/eliminate,
forfeit, freeze physics, or shorten production timers to manufacture success.
Scripted test input is not a new gameplay AI or a substitute for human feel testing.

Agent owns the independent duel fixture only. Root owns runner registration,
coordination documentation, CI inspection and any demonstrated production fix.
Under the user's revised division, A owns only menu/network/rules/world/audio
fixes. Combat, bot/weapon and control defects are reported to B.
If the fixture cannot finish within its normal bounded match window, retain
diagnostic evidence rather than claim a gameplay defect without distinguishing
test-driver limitations from simulation behavior.

## Evidence

Final Godot 4.7.2 real-time headless run passed, exit 0 with no warnings/errors.
Remote canonical Duelist approached the braked Striker from normal 38-meter
separated spawns. Sixteen hammer hits were delivered to both peers; each round
ended through core destruction at approximately 37.0 and 88.5 seconds. The
normal first-to-two match produced score 0–2, identical complete result records
and converged health on host and remote. Both rematch votes started a fresh
active duel at 93.5 seconds with repaired zones/core, battery, heat, cooldowns,
charge, damage counters and score reset.

Run with `tools/check-gameplay.ps1 -GodotPath <Godot console executable>` or the
independent `tests/integration/natural_duel.tscn`. The normal CI now includes
this check and allows its unchanged canonical match deadlines. Fixture-only
assertions compare canonical loadout fields across JSON number normalization
and identify combat events by match, round and event ID. No production mechanic
was changed. Local log: `%TEMP%/battlebots-natural-duel-final.log`.

This proves an automated natural duel against a stationary braked defender.
It does not certify human control feel, internet impairment or 2v2 combat.
