# Nitro and charged jump — B handoff, 22 September 2026

## Implemented

- Separate Nitro and suspension perk slots; starter builds equip both. Existing
  known schema-1 saves migrate to unequipped slots, retaining all old parts.
- Shift boosts forward acceleration and speed while consuming battery. Space
  charges while grounded; release launches with force proportional to hold time.
  Inactive rounds, lost input, focus loss and menus cancel charge safely.
- B is the new default brake binding. Version-1 custom controls migrate to
  version 2, assigning Space to jump and Shift to Nitro.
- Command and bot snapshot wire contracts carry the new inputs and state.
  Client replay predicts Nitro and jump; the server remains authoritative.
- The garage exposes both perk choices and the loading tip describes controls.

## Shared surfaces for A

`project.godot` adds the actions and reassigns brake. `wire_codec.gd` is protocol
6/build `mvp-ab-14`, with command bits 6–8 and three added snapshot fields.
`mvp_session.gd` predicts the new impulses locally. The loading tip changes in
the A menu area because its former Space-to-brake text became wrong. BotView
publishes `nitro_active`, `jump_charge_fraction`, and `jump_cooldown`; the A match
HUD can consume these without adding a new server field. Existing live workers
will reject this client until a matching release is deployed.

## Validation and release

Godot 4.7.2 `tools/check-drive.ps1` passed, including baseline, heavy drive and
the new authoritative/Jolt perk test. Input preferences, controls/settings layout,
garage catalogue, loadout repair/recovery, test drive, Scorpion garage/input,
hosted admission and a zero-latency network smoke passed. The full
`tools/check-mvp.ps1` run passed through all 0/80/150 ms network profiles,
ending in `MVP PASS` (`%TEMP%/battlebots-nitro-mvp.log`).

Catalogue 9 hash:
`e8d254c8f6d2636fc2c1db7b329a78b04727f5061261a9dd8f437e9021b64bda`.
The coordinated release still requires matching client/server artifacts,
a playtest break for the single Machine restart, live `/healthz` compatibility
comparison and external private/Quick Play duels through results and rematch.
Record that evidence before claiming hosted play ready.
