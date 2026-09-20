# A — Compact combat HUD redesign

Owner A; branch `codex/a-hud-redesign`, 20 September 2026.
User requests a complete, smaller and more polished combat HUD.

Reserved paths: combat/match/practice HUD presentation, match HUD scene,
HUD composition in menu_game.gd, the explicitly requested local world-tag
suppression, and their presentation tests. Consume existing BotView and match
snapshots only. No changes to combat, controls, input actions, catalogue or
networking contracts.

Direction: compact top-center score/clock, bottom-left integrity and resources,
bottom-right weapon state/charge. Show component failures and recovery context
in a bottom-center status stack only when relevant. Remove persistent compass, redundant alive roster and
practice instructions. Preserve unavailable-data states, authoritative timers,
rebound recovery labels, palette/contrast and 100–150% text settings.

Acceptance: baseline, targeted state/session/accessibility checks and native
rendered review at 720p/1080p, including enlarged text and damaged states.

## Implemented and verified

- Active match strip is 380 × 68 logical pixels; practice is a 108px pill.
  Scores show YOU/RIVAL relative to the local team. FFA and round outcomes remain.
- Integrity/battery/heat and weapon status/charge use compact lower corners with
  original vector steel/blue housings, angular silhouettes, illuminated amber
  rails, segmented bars and a circular charge instrument. The match strip uses
  separate score wings around a timer shield. No raster or external assets.
  Only failed components reveal chips; recovery is contextual. Warnings,
  recovery and failure chips now stack at bottom center per user feedback;
  captions align immediately above the stack. The old compass,
  alive roster, repeated practice target readout and permanent diagnostics are
  absent during fighting. Existing player world health bars remain unchanged;
  the explicit follow-up removes the local floating YOU text and leader only.
- Diagnostics are available in pause, with an actionable connection-degraded
  indicator during play. Both Escape and the Resume button collapse diagnostics
  so a hidden expanded panel cannot suppress the scoreboard.
- Native D3D12 Foundry practice captures reviewed at 720p and 1080p, including
  150% high-contrast text. Independent authored layout covers 720p, 1080p and
  ultrawide × 100/125/150%; healthy cards occupy 7.84% at 720p. Additional match
  strip layout checks cover 4K. Real user combat readability remains playtest work.
- Godot 4.7.2 baseline passes. Combat HUD state and real ENet propagation checks,
  composed game/pause/settings/reset tests, all palette/contrast checks, match
  state/layout tests and real UDP lobby lifecycle pass. The new compact layout
  fixture is registered in check-presentation.ps1.
- Review caught and fixed caption height at 150%, Resume diagnostics state, and
  restoring secondary text colors after cancelling high-contrast preview.
- The first lobby test ran without its prescribed 60 FPS cap and exhausted
  frame-bounded transition waits. The prescribed capped invocation passes without
  changing game behavior. Some headless menu fixture exits emitted intermittent
  2/8-ObjectDB warnings; native captures and the final verbose reproduction exited
  cleanly. No leak cause is claimed.

This is a client HUD source change. Build/protocol/catalogue remain unchanged;
there is no hosted gameplay/compatibility deployment or new online release claim.
Pre-existing project.godot editor serialization and runtime texture import changes
are preserved separately from this task. No paths remain reserved after merge.

## Follow-up scope — local floating identity

The user explicitly requests removal of the floating YOU tag. A's narrow
`BotWorldMarkers` follow-up keeps the local marker entry and B's published
[fixed green/red health bar](B_PLAYER_HEALTH_BARS.md), while leaving its label
empty and hiding its leader stem. Selection follows the published `local_entity`
identity; changing local identity restores the former local bot's rival label
and stem. Opponent/target names, OUT text, health colors/fill, fixed geometry,
occlusion and removal semantics remain unchanged. No bot/combat/control or
network data changes. Independent identity-switch and actual practice tests
cover the local tag removal while preserving health feedback.

Godot 4.7.2 at 60 FPS: independent world markers, existing fixed health-bar
acceptance, actual practice composition and real ENet HUD propagation all pass.
Native D3D12 practice also passes; the 1080p capture confirms a health-only local
marker with target name/stem and both health bars intact.
