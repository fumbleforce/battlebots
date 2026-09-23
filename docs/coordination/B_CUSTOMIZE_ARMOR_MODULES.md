# B Customize armor modules — 23 September 2026

Owner: B. Issue: [#30](https://github.com/fumbleforce/battlebots/issues/30).
Branch: `codex/b-customize-armor-modules`, based on `origin/main` at `1933bde`.

## Behavior

User request: move everything from the Customize VEHICLE tab into PARTS > ARMOR,
as vertical sections of category headings with their choices below.

- The VEHICLE tab is gone. Customize has PARTS and PAINT.
- PARTS > ARMOR shows these sections on the right, in order:
  1. ARMOR PACKAGE: the light/standard/heavy gameplay part, still filtered
     by build compatibility.
  2. One section per former vehicle module category: ARMOR SIDE, ARMOR TOP,
     ARMOR FRONT, ARMOR REAR, EXHAUST.
- Each heading starts a new grid row, and blank cells complete short rows.
  Paging never leaves a heading alone at the bottom of a page.
- A module choice edits the draft immediately and records undo history, as
  before. The description follows the last clicked choice in any section. The
  count sums all sections.
- `Customize.choice_tile(tab, category, item)` returns a listed tile for
  keyboard or test lookup, since section headings shift child positions.

## Compatibility

Presentation only. Module choices remain in `cosmetics.sawblade`, and
`PlayerProfile.catalogue.decals` / `equip("decals", ...)` are unchanged. There is
no catalogue, loadout schema, protocol, or hosted-service change, and no server
release is needed. The hidden `TabDecals` node remains in the supplied scene.

## Validation (Godot 4.7.2)

Updated checks:
- `menu_customization_screens_test`:
  - no VEHICLE tab
  - section headings are in order and start on their own rows
  - a module tile equips, is described, shows EQUIPPED, and undoes
- `garage_pagination_test`: PARTS/PAINT at 100–150% text. The full-page rule
  counts a heading together with its first row.
- `garage_comparison_panel_test`: tiles are looked up with `choice_tile`.
- `sawblade_test`: the module layout is checked at 150% through PARTS > ARMOR.

Also passing: garage history/profile/compatible parts/menu text screens,
unlocked options, customize text, repair, recovery, catalogue text,
test-drive entry, Scorpion garage, preview and `tools/check-baseline.ps1`.
Native 1920×1080 captures at 100% and 150% text were reviewed.

Remaining: human playtest.
