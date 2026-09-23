#!/usr/bin/env node
// Native diagnostic for #18. Known engine leaks are counted, never hidden.
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const options = { godot: 'godot', cycles: 10, output: '' };
for (let i = 0; i < args.length; i++) {
  const key = args[i].replace(/^--/, '');
  if (!Object.hasOwn(options, key) || !args[i + 1]) {
    throw new Error('Usage: node tools/check-scorpion-lifecycle.mjs [--godot path] [--cycles 10] [--output directory]');
  }
  options[key] = args[++i];
}
const cycles = Number(options.cycles);
if (!Number.isInteger(cycles) || cycles < 3 || cycles > 100) throw new Error('cycles must be 3–100');
const output = options.output ? resolve(options.output) : mkdtempSync(join(tmpdir(), 'scorpion-lifecycle-'));
mkdirSync(output, { recursive: true });
const minimal = join(output, 'minimal');
mkdirSync(minimal, { recursive: true });
writeFileSync(join(minimal, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Reflection atlas lifecycle"\n[rendering]\nrenderer/rendering_method="forward_plus"\nreflections/reflection_atlas/reflection_size=256\n');
copyFileSync(join(root, 'battlebots/tests/presentation/reflection_atlas_repro.gd'), join(minimal, 'repro.gd'));

function invoke(name, argv) {
  const result = spawnSync(options.godot, argv, { encoding: 'utf8', timeout: Math.max(180000, cycles * 10000), maxBuffer: 32 * 1024 * 1024 });
  const log = (result.stdout ?? '') + (result.stderr ?? '');
  writeFileSync(join(output, `${name}.log`), log);
  if (result.error || result.status !== 0 || /SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE/m.test(log)) {
    throw new Error(`${name} failed: ${result.error ?? result.status}; see ${output}`);
  }
  return log;
}
const version = invoke('version', ['--version']).trim();
if (!version.startsWith('4.7.2.stable')) throw new Error(`Expected pinned Godot 4.7.2 stable; got ${version}`);
invoke('import', ['--headless', '--path', join(root, 'battlebots'), '--editor', '--import', '--quit']);
const report = { version, cycles, generatedAt: new Date().toISOString(), upstream: 'https://github.com/godotengine/godot/issues/122498', results: [] };
const cases = [
  ...['model', 'visual', 'bot', 'arena', 'world', 'world_no_reflections'].map(mode => ({
    name: mode, path: join(root, 'battlebots'), script: 'res://tests/presentation/scorpion_lifecycle_test.gd',
    args: [`--mode=${mode}`], leaks: ['arena', 'world'].includes(mode) ? 7 : 0, growth: 0,
  })),
  { name: 'minimal_no_probe', args: ['--replace-world', '--no-probe'], leaks: 0, growth: 0 },
  { name: 'minimal_shared_world', args: [], leaks: 7, growth: 0 },
  { name: 'minimal_replaced_world', args: ['--replace-world'], leaks: 7 * cycles, growth: 3 * 1024 * 1024 },
];
for (const test of cases) {
  console.log(`Checking ${test.name} (${cycles} cycles)...`);
  const log = invoke(test.name, ['--path', test.path ?? minimal, '--rendering-method', 'forward_plus', '--max-fps', '60', '--script', test.script ?? 'res://repro.gd', '--', `--cycles=${cycles}`, ...test.args]);
  if (!/(SCORPION LIFECYCLE|REFLECTION REPRO) PASS/.test(log)) throw new Error(`${test.name}: missing completion marker`);
  const leaks = [...log.matchAll(/(\d+) RIDs of type "Texture" were leaked\./g)].reduce((sum, match) => sum + Number(match[1]), 0);
  const unexpectedLeaks = log.split('\n').filter(line => /leaked|still in use at exit/i.test(line) && !/\d+ RIDs of type "Texture" were leaked\./.test(line));
  if (leaks !== test.leaks || unexpectedLeaks.length) throw new Error(`${test.name}: changed shutdown diagnosis (${leaks} textures, expected ${test.leaks}); see ${output}`);
  const samples = log.split('\n').filter(line => line.startsWith('LIFECYCLE ')).map(line => JSON.parse(line.slice(10)));
  const freed = samples.filter(sample => sample.phase === 'freed');
  if (freed.length !== cycles) throw new Error(`${test.name}: incomplete cycle evidence`);
  // Ignore the first cycle for renderer/font/particle cache warmup. Every later
  // cycle must plateau, except the deliberately isolated upstream world leak.
  const deltas = freed.slice(2).map((sample, index) => sample.textures - freed[index + 1].textures);
  if (deltas.some(delta => delta !== test.growth)) throw new Error(`${test.name}: unexpected texture growth ${deltas}; see ${output}`);
  for (const metric of ['resources', 'objects']) {
    // Global helper objects can finish warming later than texture/resource caches.
    const stable = metric === 'objects' ? freed.slice(-Math.max(2, Math.ceil(cycles / 3))) : freed.slice(1);
    const values = stable.map(sample => sample[metric]).filter(value => value !== undefined);
    if (values.length && Math.max(...values) - Math.min(...values) > 2) throw new Error(`${test.name}: ${metric} does not plateau`);
  }
  report.results.push({ name: test.name, renderer: log.split('\n').find(line => line.includes('Using Device')), textureRidsAtShutdown: leaks, textureGrowthPerCycle: test.growth, samples });
  writeFileSync(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`PASS ${test.name}: ${leaks} texture RIDs at shutdown; ${test.growth} bytes/cycle after warmup`);
}
console.log(`DIAGNOSIS VERIFIED; known engine bug remains. Evidence: ${output}`);
