# B Customize compatible parts and compact tiles — 23 September 2026

Owner: B. Issue: [#28](https://github.com/fumbleforce/battlebots/issues/28).
Branch: `codex/b-garage-compatible-parts`, based on `origin/main` at `62d83f1`.

## Compatible parts

User request: Garage > Customize should show only parts that are usable with
the current build. Customize previously listed every part and reported the
build invalid afterwards.

`PlayerProfile.part_fits(slot, id)` decides visibility with the authoritative
`ContentRegistry.validate`. There is no separate rule table. A part is listed
when choosing it leaves only validation reasons that *every* choice for that
slot would leave. Anything this slot could fix therefore counts against the
part:

- Scorpion lists only walking legs and Atlas MX only tracks.
- The auxiliary minigun is listed only on a body with a gun socket.
- One minigun per socket.
- Parts that would exceed 120 kg / 100 power are hidden.

Reasons outside the slot's control are ignored. On an already invalid draft,
for example one that needs Repair, other slots stay usable.

Two cases stay visible on purpose:

- **The equipped part is always listed.** Saved builds and legacy builds that
  are invalid remain repairable.
- **Every body stays selectable.** A body change still preserves all other
  selected parts (GAME_SPEC 20 September decision; `scorpion_garage_test`).
  Afterwards the now-invalid part is shown beside the parts that repair it.

The category count reads "shown / total available".

## Compact option tiles and overlap fix

User requests:
- **Shorter tiles.** The placeholder "PART ART" strip is removed. Paint
  choices keep a 16 px swatch strip, and tiles are 76 px (×text scale)
  instead of 150 px. Wrapped names still grow a tile.
- **Clipping fix.** Option contents rendered shifted up into neighbouring
  tiles. Pagination measurement resized each tile's `Inner` container, which
  grows in both directions. Measurement now restores the full-rect anchors for
  tile `Inner` and category `Pad`.
- **Page budget fix.** The Customize page budget now subtracts the hazard
  stripe. The shorter tiles exposed a latent 3 px footer overflow at 150% text.

## Compatibility and validation

This is client presentation only. There is no catalogue, loadout schema,
validation rule, protocol, or hosted-service change, and no server release is
needed.

Pinned Godot 4.7.2 checks:
- New `garage_compatible_parts_test`, registered in `check-presentation.ps1`.
  Covers body/drive/socket/budget filtering, repair visibility, part-preserving
  body switch, filtered tiles/count, tile content containment and compact
  height. The containment check was confirmed to fail without the fix.
- Existing checks updated for the new behavior:
  - `garage_comparison_panel_test` reaches its over-budget case through
    PlayerProfile, since Customize no longer offers it.
  - `customize_text_test` pages until its target tile is visible, since
    shorter tiles mean fewer pages.
- Passing: garage history, profile, customization screens, menu text screens,
  unlocked options, pagination (100–150% text), customize text, repair,
  recovery, catalogue text, comparison panel, test-drive entry, Scorpion
  garage, preview, and `tools/check-baseline.ps1`.
- Native 1920×1080 captures of the parts/paint/vehicle tabs were reviewed.

Remaining: human playtest of the filtered Customize flow.
