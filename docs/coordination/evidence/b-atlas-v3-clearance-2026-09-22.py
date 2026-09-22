"""Reproduce the bounded Atlas V3 source-mesh clearance evidence; no asset edits.

Run from the repository root with Blender and the saved source as documented in
the JSON command field. Only the sibling JSON report is written.
"""
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).with_suffix('.json')
SOURCE = ROOT / 'art_source/atlas_mx/atlas_mx.blend'
MODEL = ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'
WHEELS = [('Front', .388), ('Rear', .388), ('Roller0', .120),
          ('Roller1', .120), ('Roller2', .120), ('Return', .105)]
assert Path(bpy.data.filepath).resolve() == SOURCE.resolve(), 'Load the final Atlas source first'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(obj):
    obj.data.calc_loop_triangles()
    return BVHTree.FromPolygons(
        [obj.matrix_world @ v.co for v in obj.data.vertices],
        [tuple(t.vertices) for t in obj.data.loop_triangles], all_triangles=True)


hull = tree(bpy.data.objects['HullSurface'])
report = {
    'schema_version': 1,
    'executed_utc': datetime.now(timezone.utc).isoformat(),
    'blender_version': bpy.app.version_string,
    'command_powershell': "& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background art_source/atlas_mx/atlas_mx.blend --python docs/coordination/evidence/b-atlas-v3-clearance-2026-09-22.py",
    'working_directory': 'repository root',
    'source_blend': {'path': SOURCE.relative_to(ROOT).as_posix(), 'sha256': sha256(SOURCE)},
    'runtime_model': {'path': MODEL.relative_to(ROOT).as_posix(), 'sha256': sha256(MODEL)},
    'script_sha256': sha256(Path(__file__)),
    'method': 'World-space triangle BVHTree.overlap on the saved Blender source at its authored rest phase; both sides checked independently.',
    'central_axle_exclusion': {
        'rule': 'For each wheel/DriveSurface intersecting triangle pair, exclude only when every vertex of the stationary triangle is within wheel_radius * 0.22 + 0.0001 metres of the wheel X axis. The radial distance uses world Blender Y/Z relative to the wheel pivot.',
        'radius_multiplier': .22,
        'tolerance_m': .0001,
        'purpose': 'Permit the intentional central axle joints; all other stationary-surface intersections remain failures.'
    },
    'limits': [
        'Checks surface-triangle intersections, not volumetric containment.',
        'Authored rest phase only; no continuous-motion sweep or deformation check.',
        'Connector checks are against wheels only; connector/shoe overlap is outside this bounded check.',
        'Optional armor, weapons, physics collision shapes, gameplay and renderer materials are outside this check.',
        'Runtime GLB hash identifies the accompanying export; these BVH counts use the saved Blender source, not a separate GLB reimport.'
    ],
    'sides': {},
}
totals = dict(wheel_drive_pairs=0, wheel_hull_pairs=0, wheel_wheel_pairs=0,
              connector_wheel_pairs=0, unexpected_stationary_triangle_pairs=0,
              hull_triangle_pairs=0, wheel_wheel_triangle_pairs=0,
              connector_wheel_triangle_pairs=0, excluded_axle_triangle_pairs=0)
for side, drive_name in [('L', 'DriveLeftSurface'), ('R', 'DriveRightSurface')]:
    stationary = bpy.data.objects[drive_name]
    stationary_tree = tree(stationary)
    wheel_trees = []
    result = {'stationary_mesh': drive_name, 'wheels': [], 'wheel_pair_intersections': {}}
    for label, radius in WHEELS:
        pivot = bpy.data.objects['Wheel_' + side + '_' + label]
        obj = next(item for item in pivot.children if item.type == 'MESH')
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
    report['sides'][side] = result
report['totals'] = totals
report['passed'] = all(totals[key] == 0 for key in [
    'unexpected_stationary_triangle_pairs', 'hull_triangle_pairs',
    'wheel_wheel_triangle_pairs', 'connector_wheel_triangle_pairs'])
REPORT.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('ATLAS_V3_CLEARANCE', json.dumps({'passed': report['passed'], 'totals': totals,
                                     'runtime_model_sha256': report['runtime_model']['sha256'],
                                     'report': str(REPORT)}))
assert report['passed'], 'Unexpected mesh intersections; inspect the JSON report'
