# Reproducible Woodland texture import (#51)

The Linux hosted release stopped at its final clean-source assertion because
`conifer_branches_nor.png.import` changed while preparing the release. A fresh
Godot 4.7.2 Linux import reproduced the exact diff seen in failed CI run
35895011009 on `d6152b0`.

The committed parameters already selected VRAM compression and normal-map
handling, but the output path/dependencies and metadata still described a
non-VRAM `.ctex`. A cold import rewrote these to the `.s3tc.ctex` output and
`vram_texture=true` with `s3tc_bptc`. The matching metadata correction also landed independently in `d128a40` while
this investigation was running; it is retained during rebase. This follow-up makes the intended 3D settings explicit: mipmaps enabled and auto-detection off,
matching the other Woodland normal maps. The texture UID and PNG pixels are
unchanged. Release cleanliness and compatibility checks remain intact.

Validation on Linux with official `4.7.2.stable.ed1daf0bf`:

- Move this isolated checkout's `.godot` cache aside, import from scratch: the
  old file rewrites as above; corrected metadata remains byte-for-byte stable.
- Repeat editor import with the new cache: metadata stays unchanged.
- Baseline passes; no script/parse/error diagnostics in either fixed import.
- PNG SHA256 before/after is unchanged; no source texture or material change.

Commands from the repository root:

```sh
godot --headless --path battlebots --editor --import --quit
godot --headless --path battlebots --script res://tests/baseline_smoke.gd
node tools/prepare-hosted.mjs --godot /path/to/godot
git status --porcelain
```

Preparation must run from a clean committed tree. The existing final cleanliness
assertion is the regression gate; do not bypass it or discard generated source
changes to make a release appear reproducible. The matching release and live
acceptance evidence are recorded on [#51](https://github.com/fumbleforce/battlebots/issues/51).
