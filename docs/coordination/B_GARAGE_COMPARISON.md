# B garage part comparisons

Intent to A: `codex/b-garage-comparison` starts from main `682824b`. B reserves
new pure comparison/display helpers, Customize composition, independent B scenes
and garage checks/docs. No general menus, networking, world, combat rules,
catalogue data or shared contract changes. The model/testing subagent works on
new independent files while the primary integrates the display.

Show equipped and proposed canonical values before Equip: mass/power budgets,
core, speed, armor reduction, grip, battery, cooling and recovery duration.
Changes use neutral signed numbers rather than misleading universal green gains.
Invalid drafts retain known complete mass/power totals while unavailable derived
values stay unknown. Show candidate validation reasons; never mutate the draft,
write saves or silently equip a hovered/selected candidate. Actual preview remains
the equipped draft. Paint has no performance effect.

Acceptance: independently compare actual catalogue swaps, budget overrun/repair,
unknown IDs and malformed drafts; test no mutation or fabricated derived stats.
Verify screen refresh after Equip and Undo, inspect 1280x720 layout, run baseline
and prior garage regressions. Independent scene is registered with the runner.

Implemented: pure `GarageComparison.compare(registry, draft, slot, part_id)`
returns detached current/proposed validation summaries and candidate draft.
The display keeps mass/power fixed while further rows scroll. It does not reuse
the old speculative item deltas or color every positive number as beneficial.
Unknown/incompatible candidates fail explicitly; canonical replacement can repair
an unknown saved part. Existing editable-invalid and explicit-Save behavior stays.

Validation: Godot 4.7.2 baseline, garage history, profile and customization-screen
checks pass. Independent `garage_comparison_test.tscn` covers actual catalogue
swaps, budget repairs, malformed IDs/parts, forged stats, no-op and deep isolation.
Independent `garage_comparison_panel_test.tscn` passes headlessly and with D3D12:
actual Customize selection/Equip/Undo, 119→126 kg overrun, 126→111 kg repair,
unavailable derived values, cosmetic invariance, no save writes and 720p bounds.
Both scenes are registered in check-presentation.ps1. Rendered panel inspected.
No errors or shutdown warnings occurred in these targeted checks.

Remaining B garage scope: complete repair/persistence UX, text accessibility and
authored bot-art integration. This closes canonical part comparisons, not the
whole garage or full 1v1 game acceptance.
