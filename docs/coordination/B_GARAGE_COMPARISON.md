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
