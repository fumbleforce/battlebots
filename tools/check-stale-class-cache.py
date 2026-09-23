"""Launch the menu flow with named classes missing from the editor class cache.

python3 tools/check-stale-class-cache.py --godot <godot> [Class ...]

A checkout imported before a new `class_name` script landed launches without
an editor rescan, so that class is absent from .godot/global_script_class_cache.cfg.
Runtime code must preload such classes (see #65, #74). This removes the named
entries (default: CLASSES below), runs tests/presentation/menu_flow_test.gd
through menu, host, garage and Practice, rejects any script error even when
Godot exits zero, and restores the exact cache bytes afterwards.
Run after an editor import and never in parallel with one.
"""
import argparse, re, subprocess, sys
from pathlib import Path

# Classes added after the last stable cache that runtime code must preload.
CLASSES = ['HeatRelief', 'CoolingZoneVisuals', 'SpreeBanner', 'FrontToolTuning', 'AtlasToolVisual',
           'TurretHarpoonEffects', 'MortarAimVisual', 'GamepadInput']

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('classes', nargs='*')
args = parser.parse_args()
project = Path(__file__).resolve().parents[1] / 'battlebots'
cache = project / '.godot/global_script_class_cache.cfg'
original = cache.read_bytes()
text = original.decode('utf8').strip()
entries = re.sub(r'\}\]$', '', re.sub(r'^list=\[\{', '', text)).split('}, {')
names = args.classes or CLASSES
kept = [e for e in entries if not any('"class": &"%s"' % n in e for n in names)]
removed = len(entries) - len(kept)
if removed != len(names):
    sys.exit('Expected %d imported cache entries, found %d; run the pinned editor import first.' % (len(names), removed))
try:
    cache.write_text('list=[{' + '}, {'.join(kept) + '}]\n', encoding='utf8')
    run = subprocess.run([args.godot, '--headless', '--path', str(project), '--max-fps', '60',
                          '--script', 'res://tests/presentation/menu_flow_test.gd', '--quit-after', '6000'],
                         capture_output=True, text=True, timeout=600)
    output = run.stdout + run.stderr
    print(output)
    bad = re.search(r'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException|Program crashed', output, re.M)
    if run.returncode != 0 or bad or not re.search(r'^MENU FLOW PASS$', output, re.M):
        sys.exit('Launch with a stale class cache failed (exit %d): %s' % (run.returncode, bad.group(0) if bad else 'no PASS'))
    print('STALE CLASS CACHE STARTUP PASS (%s)' % ', '.join(names))
finally:
    cache.write_bytes(original)
