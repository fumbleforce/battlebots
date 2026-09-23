# Foundry surface source

`foundry_steel_albedo.png` was generated with the built-in imagegen tool on
2026-09-20 for this project. It is an albedo texture, not a photograph or a
measured PBR scan. The shaders supply roughness, surface variation and markings.
The requested resolution was 2048 square; the returned source is 1254 square.
VRAM compression, mipmaps and anisotropic shader sampling are enabled.

Generation prompt:

> Use case: photorealistic-natural. Asset type: seamless tileable PBR albedo texture for a 3D industrial robot combat arena floor, square 2048x2048. Primary request: orthographic straight-down material scan of a continuous battered dark gray rolled steel surface, subtle warm brown oxidation ingrained in scratches, broad irregular rubbed bare metal patches, layered fine directional scrape marks, small scuffs and faint grease residue. Realistic rich subtle material detail with large and small scale variation. Flat diffuse neutral even illumination, no directional lighting, no highlights, no shadows, no perspective, no vignette. Edge-to-edge texture only. Medium-dark charcoal and muted warm-gray palette, restrained contrast. No panels, no grid, no borders, no seams, no bolts, no holes, no lettering, no markings, no objects, no dramatic large cracks, no bright colors. Designed to repeat seamlessly over a 6-meter square of metal floor in a game; believable industrial material, not abstract noise.

## Reference lighting upgrade — 23 September 2026, issue #27

`foundry_battered_steel.png` is the new built-in imagegen albedo used by Foundry's
floor/architecture shaders. Requested 2048 square; returned **1254×1254**. It is
an AI-authored surface image, not a measured material scan. The original remains
under the generator output directory; the runtime asset is copied into this repo.
No reference screenshot is substituted for rendered game scenery.

Final generation prompt (built-in tool, no API/CLI fallback):

> Use case: photorealistic-natural. Asset type: a seamless square 2048x2048 base-color texture for a real-time 3D robot combat arena, not a scene render. Generate edge-to-edge orthographic material texture of battered rolled steel plate surface. Medium neutral gray steel with irregular broad silver abrasion patches, dense fine overlapping directional scraping and gouges from heavy robots, sparse tiny black impact pits, occasional restrained warm brown oxidation and dirty grease smears. This should look like machined arena steel with polished high spots and worn workshop metal, not concrete, stone, terrain or gravel. Complex realistic material detail at several scales, coherent and varied but no large obvious recurring stains. Neutral flat diffuse illumination suitable for albedo: no cast shadows, no bright reflections or baked specular lighting, no vignette or gradient. No grid, no panels, no panel borders, no seams, no bolts, no rivets, no holes through the surface, no markings, no text, no objects. The runtime shader adds the plate seams, fasteners, markings, normals and metallic reflections. Tile seamlessly on all four edges, square composition, full texture coverage.

The floor uses deterministic per-plate rotations/offsets to break repetition;
seams/bolts, chipped paint, roughness and restrained view-space bump are shader
layers. Geometry/collision remains flat. Steel, enamel, oxidized pipes, seating
and spectators have distinct metallic/roughness values. VRAM compression,
mipmaps and anisotropic filtering are enabled; only color samplers use
`source_color`. No generated roughness or normal map is mislabeled as measured PBR.
