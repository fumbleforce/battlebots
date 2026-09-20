# Component damage visuals — B intent

Branch `codex/b-component-damage`, from main `cffc860`. Implement GAME_SPEC section 9
recognizable intact/damaged/disabled weapon and left/right drive presentation.
Use authoritative BotView.zones (drive 100, weapon 140 maximum) and elimination;
missing/invalid data is unknown, not invented damage. No event history dependency.

B reserves a reusable damage presentation component/shader, Sawblade/Walker visual
component mapping, MvpBot/classic presentation integration, independent fixtures
and docs. All cosmetics: no collision, health, drive force, hit shape or wire/API
changes. A's audio/menu/networking/world remain unchanged. Restore original paint
and visibility on repaired/new-round snapshots; no cross-bot material mutation.

Plan: localized scorched/cracked surface staging plus bounded cosmetic smoke at
failed components. Cover authored wheels, tracks, walker and all weapons plus
classic fallback. Validate stage boundaries, malformed/missing snapshots, component
and instance isolation, restore/reset behavior and native follow-distance views.
