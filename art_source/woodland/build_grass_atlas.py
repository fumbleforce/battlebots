"""Dense grass patch cards rendered from the CC0 grass_medium_01/02 scans.

Run: blender --background --python art_source/woodland/build_grass_atlas.py -- <scan_dir>
Writes battlebots/assets/textures/woodland/grass_patches.png: a 2x4 atlas of
1024x512 cells, each an orthographic side view of a different seeded patch of
~70 scanned clumps (1.2 m wide strip). Rendered under a uniform white sky, so
colour is albedo times the patch's own occlusion. Transparent texels take the
mean blade colour, so mipmaps never pull black fringes into the blades.
"""
import bpy, sys, glob, math, random, pathlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/textures/woodland/grass_patches.png"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
scan_dir = pathlib.Path(args[0])
WIDTH, DEPTH, HEIGHT = 1.2, 0.35, 0.6
CELL_W, CELL_H, COLS, ROWS = 1024, 512, 2, 4

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
sources = []
for scan_id in ("grass_medium_01", "grass_medium_02"):
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=glob.glob(str(scan_dir / scan_id / "*.gltf"))[0])
	for o in bpy.context.scene.objects:
		if o in before or o.type != "MESH":
			continue
		o.parent = None
		bpy.ops.object.select_all(action="DESELECT")
		o.select_set(True)
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
		# Origin on the clump's footprint centre at its base.
		xs = [v.co.x for v in o.data.vertices]
		ys = [v.co.y for v in o.data.vertices]
		zs = [v.co.z for v in o.data.vertices]
		shift = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
		for v in o.data.vertices:
			v.co.x -= shift[0]
			v.co.y -= shift[1]
			v.co.z -= shift[2]
		# Skip the tiny single-leaf pieces and the dark seed-head stalks; both
		# read as black specks at gameplay distance.
		if max(o.dimensions) > 0.12 and "tall" not in o.name:
			sources.append(o)
		o.hide_render = True
print("SOURCES", len(sources))

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
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = CELL_W, CELL_H
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
cam_data = bpy.data.cameras.new("card")
cam_data.type = "ORTHO"
cam_data.ortho_scale = WIDTH
cam = bpy.data.objects.new("card", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0, -10, HEIGHT * 0.5)
cam.rotation_euler = (math.pi / 2, 0, 0)
cam_data.shift_y = 0.0

atlas = np.zeros((ROWS * CELL_H, COLS * CELL_W, 4), dtype=np.float32)
for cell in range(COLS * ROWS):
	rng = random.Random(1000 + cell)
	placed = []
	for n in range(70):
		src = rng.choice(sources)
		dup = src.copy()
		dup.hide_render = False
		scene.collection.objects.link(dup)
		s = rng.uniform(0.9, 1.6)
		dup.scale = (s, s, s * rng.uniform(0.9, 1.4))
		dup.rotation_euler = (0, 0, rng.uniform(0, math.tau))
		# Denser in the middle, thinning to the strip's ends.
		x = rng.gauss(0, WIDTH * 0.24)
		dup.location = (max(-WIDTH * 0.46, min(WIDTH * 0.46, x)), rng.uniform(-DEPTH, DEPTH), 0)
		placed.append(dup)
	path = OUT.with_name("_grass_cell.png")
	scene.render.filepath = str(path)
	try:
		bpy.ops.render.render(write_still=True)
	except RuntimeError as error:
		print("GPU render failed, using CPU:", error)
		scene.cycles.device = "CPU"
		bpy.ops.render.render(write_still=True)
	img = bpy.data.images.load(str(path))
	px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL_H, CELL_W, 4)
	r, c = divmod(cell, COLS)
	y0 = (ROWS - 1 - r) * CELL_H
	atlas[y0:y0 + CELL_H, c * CELL_W:(c + 1) * CELL_W] = px
	bpy.data.images.remove(img)
	path.unlink()
	for dup in placed:
		bpy.data.objects.remove(dup)
	print("CELL", cell)

opaque = atlas[..., 3] > 0.5
atlas[~opaque, :3] = atlas[opaque, :3].mean(axis=0)
out = bpy.data.images.new("grass_patches", COLS * CELL_W, ROWS * CELL_H, alpha=True)
out.pixels.foreach_set(atlas.ravel())
out.filepath_raw = str(OUT)
out.file_format = "PNG"
out.save()
print("GRASS ATLAS DONE", OUT)
