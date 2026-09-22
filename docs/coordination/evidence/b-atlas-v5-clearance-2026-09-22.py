"""Reproduce the bounded Atlas V5 source-mesh clearance evidence; no asset edits.

Run from the repository root with Blender and the saved source as documented in
the JSON command field. Only the sibling JSON report is written.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).with_suffix('.json')
SOURCE = ROOT / 'art_source/atlas_mx/atlas_mx.blend'
MODEL = ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path)
parser.add_argument('--model', type=Path)
parser.add_argument('--report', type=Path)
parser.add_argument('--preview', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
PREVIEW = args.preview
if PREVIEW:
    PREVIEW_ROOT = ROOT / 'battlebots/exports/atlas-source-preview'
    SOURCE = PREVIEW_ROOT / 'source/atlas_mx.blend'
    MODEL = PREVIEW_ROOT / 'runtime/atlas_mx.glb'
    REPORT = PREVIEW_ROOT / 'v5-clearance-preview.json'
SOURCE = (ROOT / args.source).resolve() if args.source else SOURCE
MODEL = (ROOT / args.model).resolve() if args.model else MODEL
REPORT = (ROOT / args.report).resolve() if args.report else REPORT
MANIFEST = MODEL.with_name('atlas_manifest.json')
track = json.loads(MANIFEST.read_text(encoding='utf-8'))['track']
assert track['count_per_side'] == 40, 'Update bounded pair coverage if the authored shoe count changes'
WHEELS = [('Front', .388), ('Rear', .388), ('Roller0', .120),
          ('Roller1', .120), ('Roller2', .120), ('Return', .105)]
assert Path(bpy.data.filepath).resolve() == SOURCE.resolve(), 'Load the matching final/preview Atlas source first'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def path_label(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def png_info(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR', 'Expected PNG with IHDR'
    width, height, depth, color_type = struct.unpack('>IIBB', data[16:26])
    return {'width': width, 'height': height, 'bit_depth': depth, 'color_type': color_type}


def tree(obj, matrix_world=None):
    obj.data.calc_loop_triangles()
    matrix_world = obj.matrix_world if matrix_world is None else matrix_world
    return BVHTree.FromPolygons(
        [matrix_world @ v.co for v in obj.data.vertices],
        [tuple(t.vertices) for t in obj.data.loop_triangles], all_triangles=True)


def belt_frame(side_sign, distance):
    """Same capsule path and X rotation as the published runtime track contract."""
    radius, half, cy = track['radius'], track['half_straight'], track['center_y']
    distance %= track['loop_length']
    if distance < 2 * half:
        y, z, angle = cy + radius, -half + distance, 0
    elif distance < 2 * half + math.pi * radius:
        angle = (distance - 2 * half) / radius
        y, z = cy + radius * math.cos(angle), half + radius * math.sin(angle)
    elif distance < 4 * half + math.pi * radius:
        y, z, angle = cy - radius, half - (distance - 2 * half - math.pi * radius), math.pi
    else:
        angle = (distance - 4 * half - math.pi * radius) / radius
        y, z = cy - radius * math.cos(angle), -half - radius * math.sin(angle)
        angle += math.pi
    return Matrix.Translation((side_sign * track['x'], -z, y)) @ Matrix.Rotation(angle, 4, 'X')


hull = tree(bpy.data.objects['HullSurface'])
report = {
    'schema_version': 1,
    'asset_revision': 'V5',
    'asset_stage': 'isolated_preview' if PREVIEW else ('explicit_paths' if args.source or args.model else 'production'),
    'executed_utc': datetime.now(timezone.utc).isoformat(),
    'blender_version': bpy.app.version_string,
    'command_powershell': "& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background " + ps_quote(path_label(SOURCE)) + " --python docs/coordination/evidence/b-atlas-v5-clearance-2026-09-22.py -- --source " + ps_quote(path_label(SOURCE)) + ' --model ' + ps_quote(path_label(MODEL)) + ' --report ' + ps_quote(path_label(REPORT)) + (' --preview' if PREVIEW else ''),
    'working_directory': 'repository root',
    'source_blend': {'path': path_label(SOURCE), 'sha256': sha256(SOURCE)},
    'runtime_model': {'path': path_label(MODEL), 'sha256': sha256(MODEL)},
    'manifest': {'path': path_label(MANIFEST), 'sha256': sha256(MANIFEST)},
    'script_sha256': sha256(Path(__file__)),
    'method': 'World-space triangle BVHTree.overlap on the saved Blender source at its authored rest phase; both sides checked independently.',
    'geometry_coverage': 'Final joined meshes include rounded wheel hardware and V5 cohesive armor. V4 wheel pair coverage and central axle exclusions remain unchanged. Additional V5 checks compare all authored shoes/connectors to their stationary drive and hull armor, and base footprint to the recorded V4 envelope.',
    'central_axle_exclusion': {
        'rule': 'For each wheel/DriveSurface intersecting triangle pair, exclude only when every vertex of the stationary triangle is within wheel_radius * 0.22 + 0.0001 metres of the wheel X axis. The radial distance uses world Blender Y/Z relative to the wheel pivot.',
        'radius_multiplier': .22,
        'tolerance_m': .0001,
        'purpose': 'Permit the intentional central axle joints; all other stationary-surface intersections remain failures.'
    },
    'limits': [
        'Checks surface-triangle intersections, not volumetric containment.',
        'Belt motion samples eight fractional shoe-pitch offsets; this is a discrete pose check, not a mathematical continuous sweep or deformation check. Wheel rotations are not sampled.',
        'Connector/shoe overlap and wheel/shoe engagement are outside this bounded check; shoe/connector checks against stationary armor have no contact exclusions.',
        'Optional armor, weapons, physics collision shapes, gameplay and renderer materials are outside this check.',
        'Runtime GLB hash identifies the accompanying export; these BVH counts use the saved Blender source, not a separate GLB reimport.'
    ],
    'sides': {},
}
totals = dict(wheel_drive_pairs=0, wheel_hull_pairs=0, wheel_wheel_pairs=0,
              connector_wheel_pairs=0, unexpected_stationary_triangle_pairs=0,
              hull_triangle_pairs=0, wheel_wheel_triangle_pairs=0,
              connector_wheel_triangle_pairs=0, excluded_axle_triangle_pairs=0,
              shoe_drive_pairs=0, shoe_hull_pairs=0,
              connector_drive_pairs=0, connector_hull_pairs=0,
              shoe_drive_triangle_pairs=0, shoe_hull_triangle_pairs=0,
              connector_drive_triangle_pairs=0, connector_hull_triangle_pairs=0)
motion = {
    'fractional_pitch_offsets': [index / 8 for index in range(8)],
    'rest_offset_covered_by': 'sides and totals at the authored rest pose',
    'method': 'Rebuild BVHs from temporary world matrices for seven additional capsule-path poses. Source objects and saved asset transforms are never mutated.',
    'contact_exclusions': 'None for shoe/connector versus stationary armor or connector versus wheels.',
    'additional_mesh_pairs': 0, 'triangle_intersections': 0, 'sides': {}}
for side, drive_name in [('L', 'DriveLeftSurface'), ('R', 'DriveRightSurface')]:
    stationary = bpy.data.objects[drive_name]
    stationary_tree = tree(stationary)
    wheel_trees = []
    result = {'stationary_mesh': drive_name, 'wheels': [], 'wheel_pair_intersections': {}}
    for label, radius in WHEELS:
        pivot = bpy.data.objects['Wheel_' + side + '_' + label]
        meshes = [item for item in pivot.children if item.type == 'MESH']
        assert len(meshes) == 1, 'Expected one complete finalized wheel mesh per pivot'
        obj = meshes[0]
        wheel_tree = tree(obj)
        wheel_trees.append((label, wheel_tree))
        center = pivot.matrix_world.translation
        hits = stationary_tree.overlap(wheel_tree)
        excluded = 0
        for stationary_index, _wheel_index in hits:
            triangle = stationary.data.loop_triangles[stationary_index]
            positions = [stationary.matrix_world @ stationary.data.vertices[v].co
                         for v in triangle.vertices]
            radial = max(math.hypot(p.y - center.y, p.z - center.z) for p in positions)
            if radial <= radius * .22 + .0001:
                excluded += 1
        hull_hits = len(hull.overlap(wheel_tree))
        unexpected = len(hits) - excluded
        result['wheels'].append({'name': pivot.name, 'radius_m': radius,
                                'mesh': obj.name, 'mesh_triangle_count': len(obj.data.loop_triangles),
                                'drive_triangle_pairs': len(hits),
                                'excluded_axle_triangle_pairs': excluded,
                                'unexpected_stationary_triangle_pairs': unexpected,
                                'hull_triangle_pairs': hull_hits})
        totals['wheel_drive_pairs'] += 1
        totals['wheel_hull_pairs'] += 1
        totals['excluded_axle_triangle_pairs'] += excluded
        totals['unexpected_stationary_triangle_pairs'] += unexpected
        totals['hull_triangle_pairs'] += hull_hits
    for index, (label, wheel_tree) in enumerate(wheel_trees):
        for other, other_tree in wheel_trees[index + 1:]:
            hits = len(wheel_tree.overlap(other_tree))
            result['wheel_pair_intersections'][label + '/' + other] = hits
            totals['wheel_wheel_pairs'] += 1
            totals['wheel_wheel_triangle_pairs'] += hits
    connector_hits = {label: 0 for label, _radius in WHEELS}
    connectors = [bpy.data.objects['TrackConnector_' + side + '_%02d' % i]
                  for i in range(40)]
    for pivot in connectors:
        meshes = [item for item in pivot.children if item.type == 'MESH']
        assert len(meshes) == 1, 'Expected one authored connector mesh per pivot'
        connector_tree = tree(meshes[0])
        for label, wheel_tree in wheel_trees:
            hits = len(connector_tree.overlap(wheel_tree))
            connector_hits[label] += hits
            totals['connector_wheel_pairs'] += 1
            totals['connector_wheel_triangle_pairs'] += hits
    result['connectors'] = {
        'node_pattern': 'TrackConnector_' + side + '_{00..39}',
        'count': len(connectors),
        'wheel_pair_checks': len(connectors) * len(WHEELS),
        'triangle_pairs_by_wheel': connector_hits,
    }
    result['belt_stationary_intersections'] = []
    for kind, prefix in [('shoe', 'Tread_'), ('connector', 'TrackConnector_')]:
        for index in range(40):
            pivot = bpy.data.objects[prefix + side + '_%02d' % index]
            meshes = [item for item in pivot.children if item.type == 'MESH']
            assert len(meshes) == 1, 'Expected one finalized belt mesh per pivot'
            belt_tree = tree(meshes[0])
            drive_hits = len(belt_tree.overlap(stationary_tree))
            hull_hits = len(belt_tree.overlap(hull))
            totals[kind + '_drive_pairs'] += 1
            totals[kind + '_hull_pairs'] += 1
            totals[kind + '_drive_triangle_pairs'] += drive_hits
            totals[kind + '_hull_triangle_pairs'] += hull_hits
            result['belt_stationary_intersections'].append({
                'name': pivot.name, 'drive_triangle_pairs': drive_hits,
                'hull_triangle_pairs': hull_hits})
    report['sides'][side] = result
    pitch = track['loop_length'] / track['count_per_side']
    side_sign = -1 if side == 'L' else 1
    side_motion = []
    for fraction in motion['fractional_pitch_offsets'][1:]:
        pose = {'pitch_offset': fraction, 'mesh_pairs': 0, 'triangle_intersections': 0,
                'intersections': []}
        for kind, prefix, phase in [('shoe', 'Tread_', 0.0), ('connector', 'TrackConnector_', 0.5)]:
            for index in range(track['count_per_side']):
                pivot = bpy.data.objects[prefix + side + '_%02d' % index]
                obj = next(item for item in pivot.children if item.type == 'MESH')
                rest_frame = belt_frame(side_sign, (index + phase) * pitch)
                frame_error = max(abs(pivot.matrix_world[row][column] - rest_frame[row][column])
                                  for row in range(4) for column in range(4))
                assert frame_error < .0001, 'Authored belt rest transform differs from manifest path: ' + pivot.name
                sampled_frame = belt_frame(side_sign, (index + phase + fraction) * pitch)
                sampled_tree = tree(obj, sampled_frame @ rest_frame.inverted() @ obj.matrix_world)
                targets = [(drive_name, stationary_tree), ('HullSurface', hull)]
                if kind == 'connector':
                    targets += [('Wheel_' + side + '_' + name, wheel_tree) for name, wheel_tree in wheel_trees]
                for target_name, target_tree in targets:
                    hits = len(sampled_tree.overlap(target_tree))
                    pose['mesh_pairs'] += 1
                    pose['triangle_intersections'] += hits
                    if hits:
                        pose['intersections'].append({'node': pivot.name, 'target': target_name,
                                                      'triangle_pairs': hits})
        motion['additional_mesh_pairs'] += pose['mesh_pairs']
        motion['triangle_intersections'] += pose['triangle_intersections']
        side_motion.append(pose)
    motion['sides'][side] = side_motion
motion['passed'] = motion['triangle_intersections'] == 0
report['sampled_belt_motion'] = motion

# This baseline is the measured V4 manifest envelope captured before V5 edits.
# Use actual base mesh vertices and ancestor-aware optional-group exclusion;
# preview cameras, stage, lights and optional addon armor do not define chassis size.
optional_names = {'ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorFront',
                  'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge'}
base_meshes = []
def collect_base(obj):
    if obj.name in optional_names:
        return
    if obj.type == 'MESH':
        base_meshes.append(obj)
    for child in obj.children:
        collect_base(child)
collect_base(bpy.data.objects['AtlasMX'])
points = [obj.matrix_world @ vertex.co for obj in base_meshes for vertex in obj.data.vertices]
godot_points = [(point.x, point.z, -point.y) for point in points]
base_bounds = {'min': [min(point[axis] for point in godot_points) for axis in range(3)],
               'max': [max(point[axis] for point in godot_points) for axis in range(3)]}
v4_bounds = {'min': [-1.218, -.554118, -1.234171], 'max': [1.218, .549, 1.234171]}
footprint_tolerance = .001
footprint_passed = all(
    base_bounds['min'][axis] >= v4_bounds['min'][axis] - footprint_tolerance
    and base_bounds['max'][axis] <= v4_bounds['max'][axis] + footprint_tolerance
    for axis in [0, 2])
report['footprint'] = {
    'coordinate_system': 'Godot metres: X right, Y up, -Z forward',
    'base_meshes_checked': len(base_meshes), 'actual_base_bounds': base_bounds,
    'baseline_v4_bounds': v4_bounds,
    'baseline_v4_runtime_model_sha256': '98bfad6950c3397c26a0d1863293e4316a290db690deedca8c6b456faa318b06',
    'checked_axes': ['X', 'Z'], 'tolerance_m': footprint_tolerance,
    'height_is_informational': True, 'passed': footprint_passed}

# Observe shared mesh and UV variation in the saved asset. These counts are
# metadata rather than assertions that mirror a requested implementation count.
tread_data = {}
for side in ['L', 'R']:
    for index in range(track['count_per_side']):
        pivot = bpy.data.objects['Tread_' + side + '_%02d' % index]
        obj = next(item for item in pivot.children if item.type == 'MESH')
        key = obj.data.as_pointer()
        if key not in tread_data:
            uv_layer = obj.data.uv_layers.active
            uv_values = [coordinate for loop in uv_layer.data for coordinate in loop.uv] if uv_layer else []
            uv_bytes = struct.pack('<%df' % len(uv_values), *uv_values)
            tread_data[key] = {
                'mesh_datablock': obj.data.name, 'instance_count': 0,
                'vertices': len(obj.data.vertices), 'polygons': len(obj.data.polygons),
                'uv_layer': uv_layer.name if uv_layer else None,
                'uv_loop_count': len(uv_layer.data) if uv_layer else 0,
                'uv_layout_sha256': hashlib.sha256(uv_bytes).hexdigest() if uv_layer else None,
            }
        tread_data[key]['instance_count'] += 1
report['tread_variation'] = {
    'instances': sum(item['instance_count'] for item in tread_data.values()),
    'unique_mesh_datablocks': len(tread_data),
    'unique_uv_layouts': len({item['uv_layout_sha256'] for item in tread_data.values()
                              if item['uv_layout_sha256'] is not None}),
    'uv_hash_encoding': 'IEEE-754 float32 little-endian UV coordinates in mesh loop order',
    'variants': sorted(tread_data.values(), key=lambda item: item['mesh_datablock'])}
material_maps = []
for family in ['Primary', 'Secondary', 'Track', 'Hardware']:
    roles = ['base', 'normal', 'orm'] + (['coverage'] if family in ['Primary', 'Secondary'] else [])
    for role in roles:
        name = 'Atlas_Surface' + family + '_' + role
        path = MODEL.parent / (name + '.png')
        image = bpy.data.images.get(name)
        assert image is not None and image.packed_file is not None, 'Missing packed map: ' + name
        packed = bytes(image.packed_file.data)
        disk = path.read_bytes()
        disk_info = png_info(disk)
        packed_info = png_info(packed)
        expected_color_space = 'sRGB' if role == 'base' else 'Non-Color'
        material_maps.append({
            'name': name, 'path': path_label(path),
            'sha256': hashlib.sha256(disk).hexdigest(),
            'packed_sha256': hashlib.sha256(packed).hexdigest(),
            'disk_png': disk_info, 'packed_png': packed_info,
            'packed_matches_disk': packed == disk,
            'blender_float_buffer': image.is_float,
            'colorspace': image.colorspace_settings.name,
            'passed': disk_info['bit_depth'] == 8 and packed_info['bit_depth'] == 8
                      and packed == disk and not image.is_float
                      and image.colorspace_settings.name == expected_color_space,
        })
report['material_maps'] = {'expected_count': 14, 'checked_count': len(material_maps),
                           'passed': len(material_maps) == 14 and all(item['passed'] for item in material_maps),
                           'maps': material_maps}
assert sha256(SOURCE) == report['source_blend']['sha256'], 'Source changed during this check; rerun after the build completes'
assert sha256(MODEL) == report['runtime_model']['sha256'], 'Runtime model changed during this check; rerun after the build completes'
assert sha256(MANIFEST) == report['manifest']['sha256'], 'Manifest changed during this check; rerun after the build completes'
report['totals'] = totals
report['geometry_passed'] = all(totals[key] == 0 for key in [
    'unexpected_stationary_triangle_pairs', 'hull_triangle_pairs',
    'wheel_wheel_triangle_pairs', 'connector_wheel_triangle_pairs',
    'shoe_drive_triangle_pairs', 'shoe_hull_triangle_pairs',
    'connector_drive_triangle_pairs', 'connector_hull_triangle_pairs'])
report['passed'] = report['geometry_passed'] and report['material_maps']['passed'] and footprint_passed and motion['passed']
REPORT.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('ATLAS_V5_CLEARANCE', json.dumps({'passed': report['passed'], 'totals': totals,
                                     'packed_8bit_material_maps': len(material_maps),
                                     'footprint_passed': footprint_passed,
                                     'sampled_motion_passed': motion['passed'],
                                     'sampled_motion_additional_pairs': motion['additional_mesh_pairs'],
                                     'tread_mesh_variants': report['tread_variation']['unique_mesh_datablocks'],
                                     'tread_uv_variants': report['tread_variation']['unique_uv_layouts'],
                                     'runtime_model_sha256': report['runtime_model']['sha256'],
                                     'report': str(REPORT)}))
assert report['passed'], 'V5 geometry, footprint or packed-map check failed; inspect the JSON report'
