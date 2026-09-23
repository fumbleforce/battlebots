"""Conifer foliage cards rendered from the CC0 Poly Haven fir_sapling_medium scan.

Run: blender --background --python art_source/woodland/build_conifer_atlas.py -- <scan_dir>
<scan_dir>/fir_sapling_medium holds the 1k glTF package (see CREDITS.md).

Writes RGBA PNGs to battlebots/assets/textures/woodland/:
- conifer_sides.png: 3x2 atlas (512x1024 cells, row-major a0 a1 b0 / b1 c0 c1:
  saplings a/b/c, two orthogonal views each) for crossed billboard cards;
  trunk base at each cell's bottom centre, apex at the top.
  (Near pines use build_branch_atlas.py branch cards instead of whorl discs.)
Colour is rendered under a uniform white sky with no sun, so it is albedo
multiplied by the scan's own sky occlusion: dense inner needles darken, tips
stay bright. The game adds its own directional light on top.
"""
import bpy, sys, glob, math, pathlib, mathutils

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/textures/woodland"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
scan_dir = pathlib.Path(args[0])

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=glob.glob(str(scan_dir / "fir_sapling_medium" / "*.gltf"))[0])
saplings = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"], key=lambda o: o.name)
for o in saplings:
	o.parent = None

scene = bpy.context.scene
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
for device_type in ("OPTIX", "CUDA"):
	try:
		prefs.compute_device_type = device_type
		prefs.get_devices()
		if any(d.type == device_type for d in prefs.devices):
			for d in prefs.devices:
				d.use = d.type == device_type
			scene.cycles.device = "GPU"
			break
	except TypeError:
		continue
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

camera_data = bpy.data.cameras.new("card")
camera_data.type = "ORTHO"
camera = bpy.data.objects.new("card", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera

def render(path, width, height):
	scene.render.resolution_x = width
	scene.render.resolution_y = height
	scene.render.filepath = str(path)
	try:
		bpy.ops.render.render(write_still=True)
	except RuntimeError as error:
		print("GPU render failed, using CPU:", error)
		scene.cycles.device = "CPU"
		bpy.ops.render.render(write_still=True)

def bounds(obj):
	points = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
	low = mathutils.Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
	high = mathutils.Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
	return low, high

# Side views: 1:2 cards, trunk base at the bottom edge centre.
for index, sapling in enumerate(saplings):
	for other in saplings:
		other.hide_render = other is not sapling
	low, high = bounds(sapling)
	centre = (low + high) * 0.5
	height = high.z - low.z
	width = height * 0.5
	for view, angle in enumerate([0.0, math.pi * 0.5]):
		direction = mathutils.Vector((math.sin(angle), -math.cos(angle), 0.0))
		camera.location = mathutils.Vector((centre.x, centre.y, low.z + height * 0.5)) + direction * 50.0
		camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
		camera_data.ortho_scale = height
		camera_data.clip_start = 0.1
		camera_data.clip_end = 100.0
		render(OUT / ("conifer_side_%s%d.png" % ("abc"[index], view)), 512, 1024)
		print("CARD side", "abc"[index], view, "height", round(height, 2), "width", round(width, 2))

# Whorl slices from the tallest sapling: top-down, clipped to a thin slab.
sapling = saplings[0]
for other in saplings:
	other.hide_render = other is not sapling
low, high = bounds(sapling)
centre = (low + high) * 0.5
height = high.z - low.z
span = max(high.x - low.x, high.y - low.y)
camera.rotation_euler = (0.0, 0.0, 0.0)
camera_data.ortho_scale = span * 0.8
for n, t in enumerate([0.28, 0.4, 0.52, 0.64]):
	level = low.z + height * t
	camera.location = mathutils.Vector((centre.x, centre.y, high.z + 10.0))
	camera_data.clip_start = (high.z + 10.0) - (level + 0.45)
	camera_data.clip_end = (high.z + 10.0) - (level - 0.45)
	render(OUT / ("conifer_whorl_%d.png" % n), 1024, 1024)
	print("CARD whorl", n, "level", round(level, 2), "span", round(span * 0.8, 2))
# Pack into two atlases: sides 3 columns x 2 rows (512x1024 cells), whorls 2x2.
import numpy as np
def pack(paths, columns, cell_w, cell_h, out_name):
	rows = (len(paths) + columns - 1) // columns
	atlas = np.zeros((rows * cell_h, columns * cell_w, 4), dtype=np.float32)
	for i, path in enumerate(paths):
		img = bpy.data.images.load(str(path))
		if img.size[0] != cell_w:
			img.scale(cell_w, cell_h)
		px = np.array(img.pixels[:], dtype=np.float32).reshape(cell_h, cell_w, 4)
		# Blender pixel rows start at the bottom; atlas row 0 is the top cell.
		r, c = divmod(i, columns)
		y0 = (rows - 1 - r) * cell_h
		atlas[y0:y0 + cell_h, c * cell_w:(c + 1) * cell_w] = px
		bpy.data.images.remove(img)
		path.unlink()
	# Transparent texels take the mean foliage colour so mipmaps never pull
	# dark fringes into the needles.
	opaque = atlas[..., 3] > 0.5
	atlas[~opaque, :3] = atlas[opaque, :3].mean(axis=0)
	out = bpy.data.images.new(out_name, columns * cell_w, rows * cell_h, alpha=True)
	out.pixels.foreach_set(atlas.ravel())
	out.filepath_raw = str(OUT / (out_name + ".png"))
	out.file_format = "PNG"
	out.save()
	print("ATLAS", out_name, columns * cell_w, rows * cell_h)
pack([OUT / ("conifer_side_%s%d.png" % (v, k)) for v in "abc" for k in range(2)], 3, 512, 1024, "conifer_sides")
for n in range(4):
	(OUT / ("conifer_whorl_%d.png" % n)).unlink(missing_ok=True)
print("CONIFER ATLAS DONE")
