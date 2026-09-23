"""Game-ready Woodland boulders from CC0 Poly Haven granite scans.

Run: blender --background --python art_source/woodland/build_boulders.py -- <scan_dir>
<scan_dir> holds one folder per scan id with the 2k glTF package from Poly Haven
(see CREDITS.md). Each scan is decimated to a game budget, its full-resolution
detail is baked into a tangent-space normal map with Cycles, and the result is
exported as battlebots/assets/models/woodland/<name>.gltf (+ .bin and JPG maps,
referenced rather than embedded so the repository stores each map once) with the scan's own
albedo and ARM maps (glTF occlusion/roughness/metallic share the ARM packing).
The same low mesh drives gameplay collision (convex hull) and rendering.
"""
import bpy, sys, pathlib, math

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/models/woodland"
OUT.mkdir(parents=True, exist_ok=True)
SCANS = {
	# scan id: (output name, target triangles)
	"namaqualand_boulder_02": ("granite_boulder_a", 3200),
	"namaqualand_boulder_03": ("granite_boulder_b", 3600),
	"namaqualand_boulder_04": ("granite_boulder_c", 3600),
	"namaqualand_boulder_05": ("granite_boulder_d", 2400),
	"namaqualand_boulder_06": ("granite_boulder_e", 2400),
}
BAKE_SIZE = 2048

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

def clear():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
		for item in list(block):
			if item.users == 0:
				block.remove(item)

def joined_scan(path):
	bpy.ops.import_scene.gltf(filepath=str(path))
	meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	bpy.ops.object.select_all(action="DESELECT")
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	high = bpy.context.view_layer.objects.active
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	# Origin at the footprint centre, slightly above the lowest point, so the
	# base can sink into terrain without floating edges.
	xs = [v.co.x for v in high.data.vertices]
	ys = [v.co.y for v in high.data.vertices]
	zs = [v.co.z for v in high.data.vertices]
	offset = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs) + (max(zs) - min(zs)) * 0.08)
	for v in high.data.vertices:
		v.co.x -= offset[0]
		v.co.y -= offset[1]
		v.co.z -= offset[2]
	high.name = "high"
	return high

for scan_id, (name, target) in SCANS.items():
	clear()
	package = scan_dir / scan_id
	gltf = next(package.glob("*.gltf"))
	high = joined_scan(gltf)
	material = high.data.materials[0]
	low = high.copy()
	low.data = high.data.copy()
	low.name = name
	bpy.context.collection.objects.link(low)
	triangles = sum(len(p.vertices) - 2 for p in high.data.polygons)
	decimate = low.modifiers.new("Game budget", "DECIMATE")
	decimate.ratio = min(1.0, target / triangles)
	decimate.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = low
	bpy.ops.object.modifier_apply(modifier=decimate.name)
	bpy.ops.object.shade_smooth()
	# Bake the scan's surface into the low mesh's own UVs.
	bake = bpy.data.images.new(name + "_nor", BAKE_SIZE, BAKE_SIZE, alpha=False, float_buffer=False)
	bake.colorspace_settings.name = "Non-Color"
	low_mat = material.copy()
	low_mat.name = name
	low.data.materials.clear()
	low.data.materials.append(low_mat)
	nodes = low_mat.node_tree.nodes
	target_node = nodes.new("ShaderNodeTexImage")
	target_node.image = bake
	nodes.active = target_node
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "GPU"
	scene.cycles.samples = 1
	scene.render.bake.use_selected_to_active = True
	size = max(low.dimensions)
	scene.render.bake.cage_extrusion = size * 0.02
	scene.render.bake.max_ray_distance = size * 0.05
	scene.render.bake.margin = 8
	bpy.ops.object.select_all(action="DESELECT")
	high.select_set(True)
	low.select_set(True)
	bpy.context.view_layer.objects.active = low
	try:
		bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
	except RuntimeError as error:
		# A busy GPU (e.g. the game running) can refuse a CUDA context.
		print("GPU bake failed, using CPU:", error)
		scene.cycles.device = "CPU"
		bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
	scene.render.image_settings.file_format = "JPEG"
	scene.render.image_settings.quality = 94
	scene.render.image_settings.color_management = "OVERRIDE"
	scene.render.image_settings.view_settings.view_transform = "Standard"
	normal_path = OUT / (name + "_nor.jpg")
	bake.save_render(str(normal_path))
	bake.filepath_raw = str(normal_path)
	bake.file_format = "JPEG"
	bake.source = "FILE"
	bake.reload()
	# Grade the desert-toned scan toward the reference's cool grey granite and
	# write it as this boulder's own albedo; ARM is kept at 1k.
	principled = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
	import numpy as np
	for socket, suffix, size, grade in (("Base Color", "_diff.jpg", 2048, True), ("Roughness", "_arm.jpg", 1024, False)):
		link = principled.inputs[socket].links[0]
		node = link.from_node
		while node.type != "TEX_IMAGE":
			node = node.inputs[0].links[0].from_node
		source = node.image
		graded = source.copy()
		graded.scale(size, size)
		if grade:
			px = np.array(graded.pixels[:], dtype=np.float32).reshape(-1, 4)
			lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
			px[:, :3] = lum[:, None] + (px[:, :3] - lum[:, None]) * 0.35
			px[:, :3] *= np.array([0.97, 1.0, 1.04], dtype=np.float32)
			graded.pixels.foreach_set(px.ravel())
		path = OUT / (name + suffix)
		# save_render writes the edited pixel buffer; plain save() would copy the
		# untouched source file. Albedo goes through Standard, data maps raw.
		scene.render.image_settings.file_format = "JPEG"
		scene.render.image_settings.quality = 92
		scene.render.image_settings.color_management = "OVERRIDE"
		scene.render.image_settings.view_settings.view_transform = "Standard" if grade else "Raw"
		graded.save_render(str(path))
		written = bpy.data.images.load(str(path))
		written.colorspace_settings.name = "sRGB" if grade else "Non-Color"
		node.image = written
	for link in list(principled.inputs["Normal"].links):
		low_mat.node_tree.links.remove(link)
	normal_map = nodes.new("ShaderNodeNormalMap")
	nodes.remove(target_node)
	baked_node = nodes.new("ShaderNodeTexImage")
	baked_node.image = bake
	low_mat.node_tree.links.new(baked_node.outputs["Color"], normal_map.inputs["Color"])
	low_mat.node_tree.links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])
	bpy.data.objects.remove(high)
	bpy.ops.object.select_all(action="DESELECT")
	low.select_set(True)
	bpy.context.view_layer.objects.active = low
	out = OUT / (name + ".gltf")
	bpy.ops.export_scene.gltf(filepath=str(out), use_selection=True, export_format="GLTF_SEPARATE",
		export_image_format="JPEG", export_jpeg_quality=92, export_apply=True)
	low_tris = sum(len(p.vertices) - 2 for p in low.data.polygons)
	print("BOULDER", name, "from", scan_id, "tris", triangles, "->", low_tris,
		"dims", tuple(round(d, 3) for d in low.dimensions))
print("BOULDERS DONE")
