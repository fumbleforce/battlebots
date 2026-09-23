# Woodland Blender-derived assets

Built with Blender 5.2.2 from CC0 Poly Haven scans (https://polyhaven.com/license).
Download each scan's glTF package into `<scan_dir>/<id>/` first, then run the
scripts from the repository root (see each script's docstring).

| Output | Script | Scan | Authors |
|---|---|---|---|
| `assets/models/woodland/granite_boulder_a..e` | `build_boulders.py` | namaqualand_boulder_02..06 (2k) | Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi |
| `assets/textures/woodland/conifer_sides.png`, `conifer_whorls.png` | `build_conifer_atlas.py` | fir_sapling_medium (1k) | Rob Tuytel, Rico Cilliers |

Boulders are decimated to 2.4-3.6k triangles, with the scan detail baked into
tangent normal maps and the albedo graded to cool grey granite. The same mesh
is rendered and used as each boulder's convex collision hull. Conifer cards are
orthographic Cycles renders under a uniform white sky (albedo x self-occlusion).
| `assets/models/woodland/scatter_pebbles`, `scatter_rocks` | `build_scatter.py` | namaqualand_rocks_01 (2k), rock_moss_set_02 (2k) | Greg Zaal, Jenelle van Heerden; Kless Gyzen |
| `assets/models/woodland/scatter_grass`, `scatter_fern` | `build_scatter.py` | grass_medium_01/02, fern_02 (1k) | Rob Tuytel, Rico Cilliers |
| `assets/textures/woodland/grass_patches.png` | `build_grass_atlas.py` | grass_medium_01/02 (1k) | Rob Tuytel, Rico Cilliers |

`battlebots/tools/bake_woodland_masks.gd` bakes `ground_masks.png` (ruts, grass,
wetness, scorch) consumed by the terrain shader and scatter placement.
