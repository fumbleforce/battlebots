# B Garage loadout links — 23 September 2026

Owner: B. Issue: [#37](https://github.com/fumbleforce/battlebots/issues/37).
Branch: `codex/b-garage-loadout-links`.

## Behavior

The user asked that clicking a Garage LOADOUT row open the matching part of
Customize.

- WEAPON opens PARTS > WEAPON.
- UTILITY / AUXILIARY GUN opens PARTS > AUXILIARY / UTILITY.
- PERKS opens PARTS > NITRO PERK.
- Customize selects that category, shows its page of part slots, and lists the
  equipped part. Plain CUSTOMIZE and BUILD NEW BOT still open the first slot.
- The third row was mislabelled "BRAKE" with a SPACE key chip even though it
  shows the Nitro/Jump perks. It now reads "PERKS" with a neutral key chip.

## Hand-off

The Garage sets the static `CustomizeRequest.slot`
(`ui/menus/scripts/customize_request.gd`) and then calls A's existing
`MenuRouter.goto("customize")`. Customize consumes and clears the request in
`_ready()`. A's MenuRouter is unchanged.

## Lesson: keep static vars off preloading scripts

A `static var` on `customize.gd` keeps that script alive until exit, and with
it every scene, class and model it preloads. The editor import step
(`check-baseline.ps1`) then reported leaked ObjectDB instances plus about 1,300
DummyMesh RIDs. PowerShell 5.1 treats that stderr output as a failure.

Put shared static state in a tiny holder class with no preloads, as
`CustomizeRequest` does. The bisect confirmed the cause: the leak disappeared
with a non-static variable and with the holder class.

## Compatibility and validation

Presentation only. There is no catalogue, save, protocol or hosted change.
#36 reserves the auxiliary-label lines of `garage.gd`; this change avoids
them, and the overlap was announced on #36.

Pinned Godot 4.7.2:
- The new `garage_loadout_links_test`, registered in `check-presentation.ps1`,
  covers:
  - each row's request
  - Customize opening at the requested category, on a visible page, with the
    equipped tile listed
  - the request being consumed once
  - the plain entry defaulting to the first slot
  - the PERKS label
- Also passing: all garage and Customize checks, and
  `tools/check-baseline.ps1`, including a clean editor import.

Remaining: human playtest.
