"""Woodland ground scatter sets from CC0 Poly Haven scans.

Run: blender --background --python art_source/woodland/build_scatter.py -- <scan_dir>
<scan_dir>/<id>/ holds each scan's glTF package (see CREDITS.md).

Writes battlebots/assets/models/woodland/scatter_<set>.gltf (+ .bin and maps),
one glTF per set with one mesh node per variant, so each set's textures are
stored once:
- scatter_pebbles: the four namaqualand_rocks_01 stones decimated to ~360
  triangles, scan detail baked into a shared tangent normal map.
- scatter_rocks: the seven mossy rock_moss_set_02 rocks at ~1400 triangles,
  also with a baked normal map.
- scatter_grass / scatter_fern: grass_medium_01/02 and fern_02 clumps kept as
  real blade geometry (alpha-masked); the largest clumps are decimated.
Every node's origin sits at its footprint centre on the lowest ground contact.
"""
import bpy, sys, glob, pathlib, math

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/models/woodland"
OUT.mkdir(parents=True, exist_ok=True)
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
scan_dir = pathlib.Path(args[0])

prefs = bpy.context.preferences.addons["cycles"].preferences
for device_type in ("OPTIX", "CUDA"):
	try:
		prefs.compute_device_type = device_type
		prefs.get_devices()
		if any(d.type == device_type for d in prefs.devices):
			for d in prefs.devices:
				d.use = d.type == device_type
			break
	except TypeError:
		continue

def reset():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
		for item in list(block):
			if item.users == 0:
				block.remove(item)

def load(scan_id):
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=glob.glob(str(scan_dir / scan_id / "*.gltf"))[0])
	objs = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in before]
	for o in objs:
		bpy.ops.object.select_all(action="DESELECT")
		o.select_set(True)
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
		# Origin on the footprint centre at the lowest point.
		xs = [v.co.x for v in o.data.vertices]
		ys = [v.co.y for v in o.data.vertices]
		zs = [v.co.z for v in o.data.vertices]
		shift = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
		for v in o.data.vertices:
			v.co.x -= shift[0]
			v.co.y -= shift[1]
			v.co.z -= shift[2]
	for o in [o for o in bpy.context.scene.objects if o.type != "MESH" and o not in before]:
		bpy.data.objects.remove(o)
	return sorted(objs, key=lambda o: o.name)

def tris(o):
	return sum(len(p.vertices) - 2 for p in o.data.polygons)

def decimate(o, target):
	if tris(o) <= target:
		return
	mod = o.modifiers.new("budget", "DECIMATE")
	mod.ratio = target / tris(o)
	mod.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier=mod.name)

def export(name, objs):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
		o.location = (0, 0, 0)
	bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".gltf")), export_format="GLTF_SEPARATE",
		use_selection=True, export_image_format="JPEG", export_jpeg_quality=90, export_apply=True)
	print("SCATTER", name, [(o.name, tris(o), tuple(round(d, 2) for d in o.dimensions)) for o in objs])

def baked_set(scan_id, name, target, bake_size, rename):
	"""Decimate every piece and bake the full scan into one shared normal map."""
	reset()
	highs = load(scan_id)
	material = highs[0].data.materials[0]
	image = bpy.data.images.new(name + "_nor", bake_size, bake_size, alpha=False)
	image.colorspace_settings.name = "Non-Color"
	low_mat = material.copy()
	low_mat.name = name
	nodes = low_mat.node_tree.nodes
	principled = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
	for link in list(principled.inputs["Normal"].links):
		low_mat.node_tree.links.remove(link)
	target_node = nodes.new("ShaderNodeTexImage")
	target_node.image = image
	nodes.active = target_node
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "GPU"
	scene.cycles.samples = 1
	scene.render.bake.use_selected_to_active = True
	scene.render.bake.use_clear = False
	scene.render.bake.margin = 6
	lows = []
	for index, high in enumerate(highs):
		low = high.copy()
		low.data = high.data.copy()
		low.name = rename(index)
		bpy.context.collection.objects.link(low)
		decimate(low, target)
		low.data.materials.clear()
		low.data.materials.append(low_mat)
		bpy.context.view_layer.objects.active = low
		bpy.ops.object.shade_smooth()
		size = max(low.dimensions)
		scene.render.bake.cage_extrusion = size * 0.03
		scene.render.bake.max_ray_distance = size * 0.06
		bpy.ops.object.select_all(action="DESELECT")
		high.select_set(True)
		low.select_set(True)
		bpy.context.view_layer.objects.active = low
		try:
			bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
		except RuntimeError as error:
			print("GPU bake failed, using CPU:", error)
			scene.cycles.device = "CPU"
			bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
		lows.append(low)
	scene.render.image_settings.file_format = "JPEG"
	scene.render.image_settings.quality = 92
	scene.render.image_settings.color_management = "OVERRIDE"
	scene.render.image_settings.view_settings.view_transform = "Raw"
	path = OUT / (name + "_nor.jpg")
	image.save_render(str(path))
	baked = bpy.data.images.load(str(path))
	baked.colorspace_settings.name = "Non-Color"
	nodes.remove(target_node)
	node = nodes.new("ShaderNodeTexImage")
	node.image = baked
	normal_map = nodes.new("ShaderNodeNormalMap")
	low_mat.node_tree.links.new(node.outputs["Color"], normal_map.inputs["Color"])
	low_mat.node_tree.links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])
	for high in highs:
		bpy.data.objects.remove(high)
	export(name, lows)

baked_set("namaqualand_rocks_01", "scatter_pebbles", 360, 1024, lambda i: "pebble_%d" % i)
baked_set("rock_moss_set_02", "scatter_rocks", 1400, 2048, lambda i: "rock_%d" % i)

for scan_id, name, budget in (("grass_medium_01", "scatter_grass", 1800), ("fern_02", "scatter_fern", 1600)):
	reset()
	objs = load(scan_id)
	if scan_id == "grass_medium_01":
		objs += load("grass_medium_02")
	for index, o in enumerate(objs):
		decimate(o, budget)
		o.name = "%s_%d" % (name.split("_")[1], index)
		bpy.context.view_layer.objects.active = o
	export(name, objs)
print("SCATTER DONE")
