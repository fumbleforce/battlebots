"""Regenerate AtlasGeometry turret tables from the audited turret manifest.

python3 tools/update-turret-geometry.py [manifest]
Writes TURRET_DEPRESSION (degrees per 5-degree bearing) and TURRET_BARRELS
(barrel offsets, source metres) so gameplay matches the exported model.
"""
import json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'battlebots/assets/models/atlas_runtime/atlas_turret_manifest.json'
data = json.loads(manifest.read_text())
target = ROOT / 'battlebots/scripts/core/atlas_geometry.gd'
source = target.read_text()
fmt = lambda values: '[' + ', '.join('%g' % v for v in values) + ']'
depression = ',\n'.join('\t"%s":%s' % (k, fmt(v)) for k, v in data['clearance']['depression_profile_degrees'].items())
barrels = ',\n'.join('\t"%s":[%s]' % (k, ', '.join(fmt(b) for b in v)) for k, v in data['barrels'].items())
source = re.sub(r'const TURRET_DEPRESSION := \{.*?\n?\}', 'const TURRET_DEPRESSION := {\n' + depression + '}', source, count=1, flags=re.S)
source = re.sub(r'const TURRET_BARRELS := \{.*?\n?\}', 'const TURRET_BARRELS := {\n' + barrels + '}', source, count=1, flags=re.S)
muzzles = ', '.join('"%s":%g' % (k, v) for k, v in data['muzzle_offsets'].items())
source = re.sub(r'const TURRET_MUZZLE := \{[^}]*\}', 'const TURRET_MUZZLE := {' + muzzles + '}', source, count=1)
target.write_text(source)
print('updated', target, 'from', manifest)
