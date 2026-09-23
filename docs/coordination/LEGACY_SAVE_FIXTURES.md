# Legacy-save regression fixtures after schema 3 (#46)

Schema 1 used five part slots: chassis, drive, weapon, **armor**, utility.
Schema 2 added nitro and suspension. Schema 3 removes the armor package.
Historical source immediately before `799f04d` (perks) and `d381376` (Atlas)
confirms those slot sets.

The perk and Atlas migration tests derived old saves by removing perks from a
current starter. After schema 3, that produced a four-part schema-1 fixture that
never represented a supported save. The production migration correctly refused
it. The Windows MVP workflow consequently stopped at `PERK ABILITIES FAIL: 1`.

The fixtures now restore the historical armor slot. Expected migrated selections
exclude only that retired package, preserve all other parts/name/paint, and keep
old perk choices or add the two unequipped defaults. Schema-2 coverage now really
sets schema version 2 and includes armor, rather than merely putting an old hash
on a current schema-3 loadout. Full input snapshots verify migration immutability.
Production migration/validation, save format and gameplay remain unchanged.

Validation: the failing perk test reproduced on pinned Godot 4.7.2 Linux; its
corrected fixture passes, including live Jolt jump, heat, replay and wire checks.
The Atlas fixture's migration failures disappear; its separate hard-coded mass
expectation is tracked with #49's mass/budget test updates. Do not suppress that
failure or call the entire catalogue suite green before those updates land.
