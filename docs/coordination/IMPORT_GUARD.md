# Import guard: no stale art after a pull

Problem (user report, 23 September 2026): after `git pull` brought rebuilt bot
models, the game still showed the old ones. Godot re-imports changed assets
only when the editor runs; a game launched straight from a checkout
(`godot --path battlebots`) keeps loading the old copies in `.godot/imported`.
A git hook would need per-clone setup, so the fix lives in the project and
works for every checkout and pull with nothing to install.

`ImportGuard` (`scripts/core/import_guard.gd`) is the first autoload. When the
game runs from source with a window, it walks every tracked `.import` file
(skipping `.gdignore` folders like Godot does) and compares the source with the
hash Godot recorded at its last import, hashing only files modified since then
(about 0.1 s on a clean checkout). If an asset changed or was never imported,
it deletes that asset's outdated imported files (the editor's own file cache
can otherwise skip them), runs `godot --headless --editor --import --quit`,
checks again and relaunches the game once with the same arguments.

It never runs in the editor, exported builds (the hosted server and released
clients), headless runs (tests and CI import explicitly) or when
`BATTLEBOTS_SKIP_IMPORT_GUARD` is set. A relaunched game carries
`BATTLEBOTS_IMPORT_GUARD_RELAUNCHED` and does not check again, and if an import
fails to refresh the assets it logs an error and continues instead of looping.

Validation: `tests/presentation/import_guard_test.gd` (fixture staleness rules
and a current checkout reads fresh). Native end to end on Linux: an asset whose
bytes changed (as after a pull) was re-imported with one relaunch, then again
after restoring it with `git checkout`; no loop, no script errors. An earlier
version that trusted the import alone looped, because the editor's file cache
skipped the asset; the purge, re-check and relaunch marker prevent that.
Windows was not tested.
