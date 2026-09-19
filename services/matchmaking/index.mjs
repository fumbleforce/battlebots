import { readFile } from 'node:fs/promises';
import { resolve, isAbsolute } from 'node:path';
import { createService } from './service.mjs';
import { processWorkerFactory } from './worker.mjs';
import { resolveGameAddress } from './address.mjs';

function positiveInteger(name, fallback) {
  const value = process.env[name] === undefined ? fallback : Number(process.env[name]);
  if (!Number.isInteger(value) || value <= 0) throw new Error(`Invalid ${name}`);
  return value;
}

async function main() {
  const manifestPath = process.env.BUILD_MANIFEST_PATH;
  if (!manifestPath || !isAbsolute(manifestPath)) throw new Error('BUILD_MANIFEST_PATH must be absolute');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  const localMode = process.env.LOCAL_MODE === '1';
  const publicAddress = await resolveGameAddress(process.env.PUBLIC_ADDRESS || (localMode ? '127.0.0.1' : ''));
  const workerFactory = processWorkerFactory({
    executable: process.env.GODOT_PATH,
    projectPath: process.env.GODOT_PROJECT_PATH,
    workDirectory: resolve(process.env.STATE_DIRECTORY || process.env.ALLOCATION_DIRECTORY || './allocations'),
    log: code => process.stderr.write(`${code}\n`),
  });
  const service = createService({
    manifest: { build: manifest.build, protocol: manifest.protocol, content_hash: manifest.content_hash },
    region: process.env.REGION || 'arn', publicAddress,
    trustFlyProxy: process.env.TRUST_FLY_PROXY === '1',
    bindAddress: process.env.BIND_ADDRESS || (localMode ? '127.0.0.1' : 'fly-global-services'),
    firstPort: positiveInteger('FIRST_UDP_PORT', 24570), portCount: positiveInteger('MAX_WORKERS', 4),
  }, { workerFactory, log: code => process.stderr.write(`${code}\n`) });
  const address = await service.listen(positiveInteger('PORT', 8080), process.env.HOST || process.env.HTTP_BIND_ADDRESS || '0.0.0.0');
  process.stdout.write(`MATCHMAKING READY port=${address.port}\n`);
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return;
    stopping = true;
    await service.close();
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch(() => { process.stderr.write('MATCHMAKING START FAILED: check manifest and server configuration.\n'); process.exitCode = 1; });
