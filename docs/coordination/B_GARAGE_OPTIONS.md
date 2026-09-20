# Garage options and body selection — B implementation

Branch `codex/b-garage-options`, from main `cffc860`. User-requested scope supersedes
old multiple-size chassis and model-lock behavior. Only the authored Sawblade body
is offered. Compact, Wide and the Classic placeholder are no longer selectable.
The canonical `balanced` ID represents that offered body; legacy part IDs remain
read-compatible so loading an older save does not erase its other selections.

## Behavior and ownership

Garage build rows and Customize categories/choices pack measured rows into the
available vertical space, accounting for wrapped text, footer/actions and text
scale. A following page starts when its next row cannot fit. Paging remains for
smaller windows; resizing preserves the selected build/option and hidden pages
cannot take keyboard focus. B's layout changes leave A's main/menu flow unchanged.

All existing part, paint and module options are selectable. Mass/power limits still
explain invalid combinations and guard Save/Ready; selection never substitutes a
weapon or drive. Body edits change the body selection while retaining other part
IDs and existing appearance values. New presets use the authored body. Legacy
valid saves gain the authored appearance in the editable draft, retaining equipment
and stored paint; only an explicit Save writes the file. A legacy body size can be
replaced with the offered body without changing the remaining selections.

Authored saw/hammer/lifter visuals remain. Both spinners now use canonical weapon
presentation on the authored body, with canonical dimensions and state animation.
Legacy classic walker records also render legs. No drive force, hit shape, combat
state, input command, BotView or wire field changes.

Overall Paint applies its preset to primary/secondary body panels; individual
channels and vehicle modules remain editable. Removed compatibility-lock comments.
Save/recovery comparisons normalize JSON number representation so module integers
read back as floats cannot duplicate unchanged saved builds during reload.

## Compatibility

Catalogue revision 6 hash:
`63b655000dc8129c3cd52cb735ecfaec5cbc7cdb1513b43de024383e7473e8a5`.
Known revision-five hash
`2e559b989e4c9c990ca276bd4a319b707bb23a7b1796242444979a2736edb959`
joins earlier known-save migrations. Migration retains part IDs and cosmetics;
unknown/corrupt saves remain repairable, never silently replaced. Strict peer
content matching remains. A must deploy matching hosted worker/export content
before these clients can use hosted multiplayer. This B task does not deploy it.

## Validation

- ALL BODY WEAPONS PASS: all 20 drive/weapon combinations in real preview/native
  bot assembly, fallback geometry/animation, authored body and collision isolation.
- GARAGE UNLOCKED OPTIONS PASS: single body, every option available, body edit
  preservation, undo/redo, all combinations, modules/paint, legacy migration/reload.
- GARAGE PAGINATION PASS: dynamic layout, wrapped rows, scaling and resizing;
  native captures verify the actual controls, not just computed capacities.
- Existing Sawblade suite passes, including physics, save/profile/history/recovery,
  text, weapon controls and real ENet 0/80 ms cases. Updated obsolete tests to use
  available parts while retaining budget, undo, comparison and repair assertions.
- Featured vehicle menu, unsaved Test Drive and comparison-panel checks pass.

Native rendering and deterministic checks do not replace human gameplay acceptance.
Damage visuals remain the next separate B feature; its earlier intent branch is
unimplemented and is not a dependency of this garage change.
