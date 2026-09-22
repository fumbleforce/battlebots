"""Geometry-aware, portable Atlas material baking for Blender 5.2.

Call after geometry modifiers are applied and before GLB/source export. This
module writes only to the supplied output directory; it does not save a blend,
export a model, or alter object transforms permanently. No downloaded textures.
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector


FAMILIES = ("Primary", "Secondary", "Track", "Hardware")
SIZES = {"Primary": 4096, "Secondary": 2048, "Track": 2048, "Hardware": 4096}


def _descendants(obj):
    yield obj
    for child in obj.children:
        yield from _descendants(child)


def _family(material):
    if material is None:
        return None
    name = material.name.lower()
    if "paintprimary" in name:
        return "Primary"
    if "paintsecondary" in name:
        return "Secondary"
    if "track" in name:
        return "Track"
    # Preserve authored emission and tiny lettering instead of baking them flat.
    if any(word in name for word in ("lamp", "lens", "stencil")):
        return None
    return "Hardware"


def _set(links, socket, value):
    if isinstance(value, bpy.types.NodeSocket):
        links.new(value, socket)
    else:
        socket.default_value = value


def _math(nodes, links, operation, a, b=0.0, clamp=False):
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    node.use_clamp = clamp
    _set(links, node.inputs[0], a)
    _set(links, node.inputs[1], b)
    return node.outputs[0]


def _mix(nodes, links, factor, a, b):
    node = nodes.new("ShaderNodeMixRGB")
    node.blend_type = "MIX"
    _set(links, node.inputs[0], factor)
    _set(links, node.inputs[1], a)
    _set(links, node.inputs[2], b)
    return node.outputs[0]


def _noise(nodes, links, position, scale, detail=2.0):
    node = nodes.new("ShaderNodeTexNoise")
    node.noise_dimensions = "3D"
    links.new(position, node.inputs["Vector"])
    node.inputs["Scale"].default_value = scale
    node.inputs["Detail"].default_value = detail
    node.inputs["Roughness"].default_value = 0.7
    return node.outputs["Fac"]


def _linear(rgb):
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb) + (1.0,)


def _image(name, size, color=(0, 0, 0, 1), data=True):
    image = bpy.data.images.new(name, width=size, height=size, alpha=True, float_buffer=True)
    image.generated_color = color
    image.colorspace_settings.name = "Non-Color" if data else "sRGB"
    return image


def _save(image, output, name):
    # File-backed inputs are lazy; load the original before changing its path.
    if not image.has_data:
        _ = image.pixels[0]
    image.name = name
    image.filepath_raw = str(output / (name + ".png"))
    image.file_format = "PNG"
    # Cycles writes sRGB-tagged bake buffers in encoded sRGB already. Standard
    # preserves that transfer (and converts scene-linear images when supplied);
    # data maps must bypass display transforms. Image.save() otherwise silently
    # saves our float bake buffers as 16-bit PNGs, bloating the runtime package.
    settings = bpy.data.scenes.new("AtlasTextureSaveSettings")
    try:
        settings.render.image_settings.file_format = "PNG"
        settings.render.image_settings.color_mode = "RGBA"
        settings.render.image_settings.color_depth = "8"
        settings.render.image_settings.compression = 80
        settings.view_settings.view_transform = "Raw" if image.colorspace_settings.is_data else "Standard"
        settings.view_settings.look = "None"
        settings.view_settings.exposure = 0.0
        settings.view_settings.gamma = 1.0
        settings.render.dither_intensity = 0.0
        image.save_render(image.filepath_raw, scene=settings)
    finally:
        bpy.data.scenes.remove(settings)
    # Coverage is consumed by the runtime shader through its filename, so it
    # has no Blender material user. Retain it in the packed editable source.
    image.use_fake_user = name.endswith("_coverage")
    # Use a file-backed image in the final graph; the exporter keeps this name.
    image.source = "FILE"
    image.reload()
    return image


def _unique_meshes(objects):
    representatives = {}
    for obj in sorted(objects, key=lambda item: item.name):
        if obj.type == "MESH":
            representatives.setdefault(obj.data.as_pointer(), obj)
    return list(representatives.values())


def _atlas_uvs(representatives, family, size):
    """Unwrap one family together, then return UVs to the original mesh loops."""
    verts, faces, sources = [], [], []
    vertex_map = {}
    for obj in representatives:
        mesh = obj.data
        for polygon in mesh.polygons:
            material = mesh.materials[polygon.material_index] if polygon.material_index < len(mesh.materials) else None
            if _family(material) != family:
                continue
            face = []
            for vertex_index in polygon.vertices:
                key = (mesh.as_pointer(), vertex_index)
                if key not in vertex_map:
                    vertex_map[key] = len(verts)
                    verts.append(obj.matrix_world @ mesh.vertices[vertex_index].co)
                face.append(vertex_map[key])
            faces.append(face)
            sources.append((mesh, tuple(polygon.loop_indices)))
    if not faces:
        return 0
    data = bpy.data.meshes.new("AtlasBakeUV_" + family)
    data.from_pydata(verts, [], faces)
    data.update()
    data.uv_layers.new(name="UVMap")
    obj = bpy.data.objects.new(data.name, data)
    bpy.context.collection.objects.link(obj)
    try:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        # A fixed pixel gutter becomes impossible for thousands of tiny hardware
        # islands at probe resolution. Bound the gutter by the face population.
        gutter = min(3.0 / size, 0.085 / math.sqrt(len(faces))) if size <= 1024 else 3.0 / size
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), margin_method="FRACTION",
                                 island_margin=gutter, area_weight=0.5,
                                 correct_aspect=False, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")
        for polygon, (mesh, loops) in zip(data.polygons, sources):
            if not mesh.uv_layers:
                mesh.uv_layers.new(name="UVMap")
            uv = mesh.uv_layers[0]
            uv.name = "UVMap"
            mesh.uv_layers.active_index = 0
            uv.active_render = True
            for source_loop, target_loop in zip(loops, polygon.loop_indices):
                uv.data[source_loop].uv = data.uv_layers.active.data[target_loop].uv
        return len(faces)
    finally:
        if obj.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(data)


def _geometry_edge_image(representatives, family, size):
    """Rasterize distance to physical bevel seams, never UV island borders."""
    pixels = np.zeros((size, size), dtype=np.float32)
    for obj in representatives:
        mesh = obj.data
        mesh.calc_loop_triangles()
        material_families = [_family(material) for material in mesh.materials]
        adjacency = {}
        for polygon in mesh.polygons:
            for edge in polygon.edge_keys:
                adjacency.setdefault(tuple(sorted(edge)), []).append(polygon)
        world = np.asarray([tuple(obj.matrix_world @ vertex.co) for vertex in mesh.vertices], dtype=np.float32)
        segments = {}
        full_edge_faces = set()
        for polygon in mesh.polygons:
            if material_families[polygon.material_index] != family:
                continue
            material = mesh.materials[polygon.material_index]
            if "paintprimaryedge" in material.name.lower():
                full_edge_faces.add(polygon.index)
                continue
            edges = []
            for key in polygon.edge_keys:
                for neighbor in adjacency[tuple(sorted(key))]:
                    if neighbor.index == polygon.index:
                        continue
                    other = mesh.materials[neighbor.material_index]
                    is_bevel = "paintprimaryedge" in other.name.lower()
                    secondary_corner = family == "Secondary" and _family(other) == family and polygon.normal.dot(neighbor.normal) < 0.94
                    if is_bevel or secondary_corner:
                        edges.append((world[key[0]], world[key[1]]))
                        break
            if edges:
                segments[polygon.index] = edges
        for triangle in mesh.loop_triangles:
            face = triangle.polygon_index
            if face not in full_edge_faces and face not in segments:
                continue
            uv = np.asarray([tuple(mesh.uv_layers[0].data[index].uv) for index in triangle.loops], dtype=np.float32) * size
            low = np.maximum(0, np.floor(uv.min(axis=0)).astype(int))
            high = np.minimum(size - 1, np.ceil(uv.max(axis=0)).astype(int))
            if np.any(high < low):
                continue
            yy, xx = np.mgrid[low[1]:high[1] + 1, low[0]:high[0] + 1]
            x, y = xx + 0.5, yy + 0.5
            denominator = (uv[1, 1] - uv[2, 1]) * (uv[0, 0] - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (uv[0, 1] - uv[2, 1])
            if abs(denominator) < 1e-8:
                continue
            a = ((uv[1, 1] - uv[2, 1]) * (x - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (y - uv[2, 1])) / denominator
            b = ((uv[2, 1] - uv[0, 1]) * (x - uv[2, 0]) + (uv[0, 0] - uv[2, 0]) * (y - uv[2, 1])) / denominator
            c = 1.0 - a - b
            valid = (a >= -1e-5) & (b >= -1e-5) & (c >= -1e-5)
            if not np.any(valid):
                continue
            if face in full_edge_faces:
                strength = np.ones(np.count_nonzero(valid), dtype=np.float32)
            else:
                vertices = world[np.asarray(triangle.vertices)]
                points = a[valid, None] * vertices[0] + b[valid, None] * vertices[1] + c[valid, None] * vertices[2]
                distance = np.full(len(points), np.inf, dtype=np.float32)
                for start, end in segments[face]:
                    axis = end - start
                    t = np.clip(np.sum((points - start) * axis, axis=1) / max(float(axis @ axis), 1e-12), 0, 1)
                    distance = np.minimum(distance, np.linalg.norm(points - start - t[:, None] * axis, axis=1))
                strength = np.clip(1.0 - distance / 0.012, 0.0, 1.0)
            py, px = yy[valid], xx[valid]
            pixels[py, px] = np.maximum(pixels[py, px], strength)
    image = _image("AtlasBake_%s_PhysicalEdges" % family, size)
    rgba = np.repeat(pixels[:, :, None], 4, axis=2)
    rgba[:, :, 3] = 1.0
    _write_pixels(image, rgba)
    return image


def _procedural(material, family, ao_image, primary_color, edge_image=None):
    """World-space wear becomes UV texture data; no procedural export required."""
    old = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    color = tuple(old.inputs["Base Color"].default_value) if old else tuple(material.diffuse_color)
    metallic = old.inputs["Metallic"].default_value if old else 0.0
    roughness = old.inputs["Roughness"].default_value if old else 0.55
    edge_role = "paintprimaryedge" in material.name.lower()
    if edge_role:
        color, metallic, roughness = primary_color, 0.08, 0.66
    # Painted secondary is enamel, not a partially metallic pseudo-material.
    if family in ("Primary", "Secondary"):
        metallic = 0.08
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    geometry = nodes.new("ShaderNodeNewGeometry")
    position = geometry.outputs["Position"]
    broad = _noise(nodes, links, position, 3.8)
    grain = _noise(nodes, links, position, 125.0)
    micro = _noise(nodes, links, position, 750.0)
    fracture = _noise(nodes, links, position, 48.0, 3.0)
    ao_node = nodes.new("ShaderNodeTexImage")
    ao_node.image = ao_image
    ao_node.interpolation = "Linear"
    ao_node.label = "Baked geometric occlusion"
    local_ao = nodes.new("ShaderNodeAmbientOcclusion")
    local_ao.only_local = True
    local_ao.inputs["Distance"].default_value = 0.06
    local_ao.samples = 16
    local_ao.label = "Finite contact AO inside this assembly only"
    dirty = _math(nodes, links, "SUBTRACT", 1.0, ao_node.outputs["Color"])
    dirty = _math(nodes, links, "MULTIPLY", dirty, 0.38, True)
    variation = _math(nodes, links, "ADD", _math(nodes, links, "MULTIPLY", broad, 0.085), 0.9475)
    color_node = nodes.new("ShaderNodeMixRGB")
    color_node.blend_type = "MULTIPLY"
    color_node.inputs[0].default_value = 1.0
    color_node.inputs[1].default_value = color
    links.new(variation, color_node.inputs[2])
    base = color_node.outputs[0]
    rough = _math(nodes, links, "ADD", roughness - 0.045, _math(nodes, links, "MULTIPLY", broad, 0.09))
    rough = _math(nodes, links, "ADD", rough, _math(nodes, links, "MULTIPLY", grain, 0.02), True)
    metal, coverage, chip = metallic, 0.0, 0.0
    if family in ("Primary", "Secondary"):
        edge_node = nodes.new("ShaderNodeTexImage")
        edge_node.image = edge_image
        edge_node.label = "Distance to physical bevel seams"
        edge = edge_node.outputs["Color"]
        boundary = _math(nodes, links, "ADD", 0.18, _math(nodes, links, "MULTIPLY", fracture, 0.60))
        primer_boundary = _math(nodes, links, "SUBTRACT", boundary, 0.065)
        chip = _math(nodes, links, "MULTIPLY", _math(nodes, links, "GREATER_THAN", edge, boundary),
                     _math(nodes, links, "LESS_THAN", fracture, 0.405))
        primer = _math(nodes, links, "MULTIPLY", _math(nodes, links, "GREATER_THAN", edge, primer_boundary),
                       _math(nodes, links, "LESS_THAN", fracture, 0.423))
        abrasion_vector = nodes.new("ShaderNodeVectorMath")
        abrasion_vector.operation = "MULTIPLY"
        links.new(position, abrasion_vector.inputs[0])
        abrasion_vector.inputs[1].default_value = (10.0, 72.0, 190.0)
        abrasion = _noise(nodes, links, abrasion_vector.outputs[0], 1.0, 1.0)
        sparse_region = _math(nodes, links, "LESS_THAN", broad, 0.42)
        face_chip = _math(nodes, links, "MULTIPLY", sparse_region, _math(nodes, links, "GREATER_THAN", abrasion, 0.70))
        face_primer = _math(nodes, links, "MULTIPLY", sparse_region, _math(nodes, links, "GREATER_THAN", abrasion, 0.685))
        chip = _math(nodes, links, "MAXIMUM", chip, face_chip)
        primer = _math(nodes, links, "MAXIMUM", primer, face_primer)
        base = _mix(nodes, links, primer, base, _linear((0.23, 0.205, 0.17)))
        base = _mix(nodes, links, chip, base, _linear((0.54, 0.565, 0.58)))
        rough = _mix(nodes, links, primer, rough, (0.77, 0.77, 0.77, 1))
        rough = _mix(nodes, links, chip, rough, (0.37, 0.37, 0.37, 1))
        metal = _mix(nodes, links, primer, (metallic, metallic, metallic, 1), (0, 0, 0, 1))
        metal = _mix(nodes, links, chip, metal, (0.94, 0.94, 0.94, 1))
        coverage = _math(nodes, links, "SUBTRACT", 1.0, primer, clamp=True)
        coverage = _math(nodes, links, "MULTIPLY", coverage, _math(nodes, links, "SUBTRACT", 1.0, dirty))
    elif metallic > 0.5:
        # Sparse anisotropic fine abrasions in object metres, not UV island borders.
        vector = nodes.new("ShaderNodeVectorMath")
        vector.operation = "MULTIPLY"
        links.new(position, vector.inputs[0])
        vector.inputs[1].default_value = (9.0, 280.0, 170.0)
        scratch = _noise(nodes, links, vector.outputs[0], 1.0, 1.0)
        scratch = _math(nodes, links, "GREATER_THAN", scratch, 0.71)
        scratch = _math(nodes, links, "MULTIPLY", scratch, 0.23)
        base = _mix(nodes, links, scratch, base, _linear((0.66, 0.675, 0.68)))
        rough = _math(nodes, links, "SUBTRACT", rough, _math(nodes, links, "MULTIPLY", scratch, 0.22), True)
    base = _mix(nodes, links, dirty, base, _linear((0.125, 0.105, 0.075)))
    rough = _math(nodes, links, "ADD", rough, _math(nodes, links, "MULTIPLY", dirty, 0.16), True)
    height = _math(nodes, links, "MULTIPLY", micro, 0.12)
    height = _math(nodes, links, "SUBTRACT", height, _math(nodes, links, "MULTIPLY", chip, 0.65))
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    bump.inputs["Distance"].default_value = 0.0005
    links.new(height, bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _set(links, bsdf.inputs["Base Color"], base)
    _set(links, bsdf.inputs["Metallic"], metal)
    _set(links, bsdf.inputs["Roughness"], rough)
    links.new(bsdf.outputs[0], output.inputs["Surface"])
    combine = nodes.new("ShaderNodeCombineColor")
    combine.mode = "RGB"
    _set(links, combine.inputs[0], coverage)
    _set(links, combine.inputs[1], rough)
    _set(links, combine.inputs[2], metal)
    emission = nodes.new("ShaderNodeEmission")
    target = nodes.new("ShaderNodeTexImage")
    target.label = "Bake target"
    nodes.active = target
    return {"output": output, "bsdf": bsdf, "emit": emission, "target": target,
            "base": base, "params": combine.outputs[0], "ao": local_ao.outputs["AO"], "family": family,
            "original_color": color, "metallic": metallic, "roughness": roughness}


def _pixels(image):
    values = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(values)
    return values.reshape(image.size[1], image.size[0], 4)


def _write_pixels(image, values):
    image.pixels.foreach_set(np.ascontiguousarray(values, dtype=np.float32).reshape(-1))
    image.update()


def _wire_final(material, maps, family, coverage_name):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(bsdf.outputs[0], output.inputs["Surface"])
    textures = {}
    for role in ("base", "orm", "normal"):
        node = nodes.new("ShaderNodeTexImage")
        node.image = maps[role]
        node.interpolation = "Linear"
        textures[role] = node
    links.new(textures["base"].outputs["Color"], bsdf.inputs["Base Color"])
    separate = nodes.new("ShaderNodeSeparateColor")
    separate.mode = "RGB"
    links.new(textures["orm"].outputs["Color"], separate.inputs["Color"])
    links.new(separate.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(separate.outputs["Blue"], bsdf.inputs["Metallic"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 1.0
    links.new(textures["normal"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    group = bpy.data.node_groups.get("glTF Material Output")
    if group is None:
        group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        group.nodes.new("NodeGroupInput")
        group.nodes.new("NodeGroupOutput")
    gltf = nodes.new("ShaderNodeGroup")
    gltf.node_tree = group
    links.new(separate.outputs["Red"], gltf.inputs["Occlusion"])
    material["atlas_surface_family"] = family
    if coverage_name:
        material["atlas_paint_coverage"] = coverage_name


def bake_surface_atlases(root, lifter, optional, runtime_path, quick=False):
    """Bake unique UV1 atlases and return JSON-serializable export metadata."""
    output = Path(runtime_path)
    output.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    objects = list(dict.fromkeys([*_descendants(root), *_descendants(lifter)]))
    meshes = [obj for obj in objects if obj.type == "MESH"]
    representatives = _unique_meshes(meshes)
    sizes = {family: (1024 if family == "Primary" else 512) if quick else SIZES[family] for family in FAMILIES}
    state = {"engine": scene.render.engine, "samples": scene.cycles.samples,
             "device": scene.cycles.device, "active": bpy.context.view_layer.objects.active,
             "selected": list(bpy.context.selected_objects),
             "bake": {name: getattr(scene.render.bake, name) for name in
                      ("use_selected_to_active", "use_clear", "margin", "margin_type", "normal_space")}}
    visibility = {obj: (obj.hide_render, obj.hide_get()) for obj in bpy.context.scene.objects}
    transforms = {obj: obj.matrix_world.copy() for obj in [*optional, lifter]}
    materials = {slot.material for obj in representatives for slot in obj.material_slots if slot.material}
    active_materials = {material: _family(material) for material in materials if _family(material)}
    previous_images = {node.image for material in active_materials for node in material.node_tree.nodes
                       if node.type == "TEX_IMAGE" and node.image}
    excluded = materials - active_materials.keys()
    original_nodes = {}
    metadata = {"version": 1, "uv": "TEXCOORD_0", "unique_meshes": len(representatives),
                "mesh_instances": len(meshes), "families": {}, "paint_coverage": {},
                "occlusion": {"method": "ray_traced_local_assembly", "distance_metres": 0.06}}
    try:
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH" and obj not in meshes:
                obj.hide_render = True
        for obj in objects:
            obj.hide_set(False)
            obj.hide_render = False
        for family in FAMILIES:
            count = _atlas_uvs(representatives, family, sizes[family])
            metadata["families"][family] = {"resolution": sizes[family], "faces": count}
            print("ATLAS_BAKE_UV", family, sizes[family], count, flush=True)
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 12 if quick else 32
        scene.render.bake.use_selected_to_active = False
        scene.render.bake.use_clear = False
        scene.render.bake.margin = 4 if quick else 8
        scene.render.bake.margin_type = "EXTEND"
        scene.render.bake.normal_space = "TANGENT"
        try:
            preferences = bpy.context.preferences.addons["cycles"].preferences
            preferences.compute_device_type = "OPTIX"
            preferences.get_devices()
            for device in preferences.devices:
                device.use = device.type == "OPTIX"
            scene.cycles.device = "GPU"
        except Exception:
            scene.cycles.device = "CPU"
        images = {family: {role: _image("AtlasBake_%s_%s" % (family, role), sizes[family],
                   color=(1, 1, 1, 1) if role == "ao" else ((0.5, 0.5, 1, 1) if role == "normal" else (0, 0, 0, 1)),
                   data=role != "base") for role in ("ao", "base", "params", "normal")} for family in FAMILIES}
        primary = next((m for m in active_materials if m.name == "Atlas_PaintPrimary"), None)
        primary_color = tuple(primary.diffuse_color) if primary else _linear((.86, .51, .055))
        edges = {family: _geometry_edge_image(representatives, family, sizes[family]) for family in ("Primary", "Secondary")}
        graphs = {material: _procedural(material, family, images[family]["ao"], primary_color, edges.get(family))
                  for material, family in active_materials.items()}
        metadata["material_references"] = {material.name: {"linear_color": list(graph["original_color"]),
            "metallic": graph["metallic"], "roughness": graph["roughness"]} for material, graph in graphs.items()}
        dummy = _image("AtlasBake_Excluded", 32)
        for material in excluded:
            original_nodes[material] = material.node_tree.nodes.active
            target = material.node_tree.nodes.new("ShaderNodeTexImage")
            target.image = dummy
            target.name = "AtlasBakeExcludedTarget"
            material.node_tree.nodes.active = target
        bpy.ops.object.select_all(action="DESELECT")
        for obj in representatives:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = representatives[0]
        # Optional parts and the separate attachment must not bake shadows onto
        # the bare base or onto one another. Keep each assembly intact.
        for index, obj in enumerate([*optional, lifter]):
            obj.matrix_world = Matrix.Translation(Vector((8.0 * (index + 1), 0, 0))) @ transforms[obj]
        bpy.context.view_layer.update()
        for role, bake_type in (("ao", "EMIT"), ("base", "EMIT"), ("params", "EMIT"), ("normal", "NORMAL")):
            # This node already traces sixteen local AO rays per sample. Extra
            # outer Cycles samples repeat the same work; colour/normal retain AA.
            scene.cycles.samples = (1 if quick else 4) if role == "ao" else (12 if quick else 32)
            if role == "base":
                for obj, transform in transforms.items():
                    obj.matrix_world = transform
                bpy.context.view_layer.update()
            for material, graph in graphs.items():
                graph["target"].image = images[graph["family"]][role]
                material.node_tree.nodes.active = graph["target"]
                links = material.node_tree.links
                if bake_type == "EMIT":
                    links.new(graph[role], graph["emit"].inputs["Color"])
                    links.new(graph["emit"].outputs[0], graph["output"].inputs["Surface"])
                else:
                    links.new(graph["bsdf"].outputs[0], graph["output"].inputs["Surface"])
            print("ATLAS_BAKE_PASS", role, flush=True)
            bpy.ops.object.bake(type=bake_type)
        final_maps = {}
        for family in FAMILIES:
            prefix = "Atlas_Surface" + family
            source = images[family]
            params, ao = _pixels(source["params"]), _pixels(source["ao"])
            occupied = params[:, :, 1] > 0.05
            if not np.any(occupied):
                raise RuntimeError("Atlas %s atlas has no baked surface pixels" % family)
            coverage = params[:, :, 0].copy()
            params[:, :, 0] = ao[:, :, 0]
            params[:, :, 3] = 1.0
            _write_pixels(source["params"], params)
            maps = {"base": _save(source["base"], output, prefix + "_base"),
                    "orm": _save(source["params"], output, prefix + "_orm"),
                    "normal": _save(source["normal"], output, prefix + "_normal")}
            if family in ("Primary", "Secondary"):
                mask = _image(prefix + "_coverage", sizes[family])
                channels = np.repeat(coverage[:, :, None], 4, axis=2)
                channels[:, :, 3] = 1.0
                _write_pixels(mask, channels)
                maps["coverage"] = _save(mask, output, prefix + "_coverage")
                metadata["paint_coverage"][family] = prefix + "_coverage.png"
            final_maps[family] = maps
            metadata["families"][family].update({"images": {key: image.name + ".png" for key, image in maps.items()},
                "occupied_fraction": round(float(occupied.mean()), 5),
                "ao_min": round(float(ao[:, :, 0][occupied].min()), 5), "ao_mean": round(float(ao[:, :, 0][occupied].mean()), 5),
                "roughness_min": round(float(params[:, :, 1][occupied].min()), 5), "roughness_max": round(float(params[:, :, 1][occupied].max()), 5)})
        for material, family in active_materials.items():
            _wire_final(material, final_maps[family], family, metadata["paint_coverage"].get(family))
        # Remove the old flat edge role from exported surfaces, after its face
        # identity has helped place irregular physical paint wear during baking.
        if primary:
            for obj in representatives:
                for slot in obj.material_slots:
                    if slot.material and "paintprimaryedge" in slot.material.name.lower():
                        slot.material = primary
        for image in previous_images:
            if image.users == 0:
                bpy.data.images.remove(image)
        for source in images.values():
            if source["ao"].users == 0:
                bpy.data.images.remove(source["ao"])
        for image in edges.values():
            if image.users == 0:
                bpy.data.images.remove(image)
        print("ATLAS_BAKE_COMPLETE", str(output), flush=True)
        return metadata
    finally:
        for obj, transform in transforms.items():
            obj.matrix_world = transform
        for material in excluded:
            node = material.node_tree.nodes.get("AtlasBakeExcludedTarget")
            if node:
                material.node_tree.nodes.remove(node)
            material.node_tree.nodes.active = original_nodes.get(material)
        if "dummy" in locals() and dummy.users == 0:
            bpy.data.images.remove(dummy)
        for obj, (render, hidden) in visibility.items():
            obj.hide_render = render
            obj.hide_set(hidden)
        scene.render.engine = state["engine"]
        scene.cycles.samples = state["samples"]
        scene.cycles.device = state["device"]
        for name, value in state["bake"].items():
            setattr(scene.render.bake, name, value)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in state["selected"]:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = state["active"]
        bpy.context.view_layer.update()
