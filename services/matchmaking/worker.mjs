import { spawn } from 'node:child_process';
import { mkdir, readFile, rename, writeFile, rm } from 'node:fs/promises';
import { resolve, join, isAbsolute } from 'node:path';

// The executable/project are operator configuration, never HTTP request values.
export function processWorkerFactory({ executable, projectPath, workDirectory, log = () => {} }, { spawnProcess = spawn } = {}) {
  if (!executable || !isAbsolute(executable)) throw new Error('GODOT_PATH must be an absolute executable path');
  if (projectPath && !isAbsolute(projectPath)) throw new Error('GODOT_PROJECT_PATH must be absolute');
  const base = resolve(workDirectory);
  return async (config, onExit) => {
    if (!/^[a-f0-9]{32}$/.test(config.allocation_id)) throw new Error('Invalid allocation ID');
    const directory = join(base, config.allocation_id);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const configPath = join(directory, 'config.json');
    const statusPath = join(directory, 'status.json');
    let revision = 0;
    const update = async (value) => {
      const temporary = `${configPath}.${++revision}.tmp`;
      await writeFile(temporary, JSON.stringify(value), { mode: 0o600 });
      await rename(temporary, configPath);
    };
    await update(config);
    const args = ['--headless', '--max-fps', '60'];
    if (projectPath) args.push('--path', projectPath);
    args.push('--', `--allocation-config=${configPath}`);
    const child = spawnProcess(executable, args, { shell: false, windowsHide: true, stdio: 'ignore' });
    let exited = false;
    let stopping = false;
    let resolveExit;
    const exitPromise = new Promise(resolveDone => { resolveExit = resolveDone; });
    const finish = () => {
      if (exited) return;
      exited = true;
      resolveExit();
      if (!stopping) onExit();
    };
    child.once('error', error => {
      const code = typeof error.code === 'string' && /^[A-Z_]{1,32}$/.test(error.code) ? error.code : 'UNKNOWN';
      log(JSON.stringify({ event: 'worker_spawn_failed', allocation_id: config.allocation_id, code }));
      finish();
    });
    child.once('exit', (code, signal) => {
      log(JSON.stringify({ event: 'worker_exit', allocation_id: config.allocation_id, code, signal, expected: stopping }));
      finish();
    });
    return {
      update,
      async status() {
        try {
          const raw = await readFile(statusPath);
          if (raw.length > 16_384) return null;
          return JSON.parse(raw.toString('utf8'));
        } catch { return null; }
      },
      async stop() {
        stopping = true;
        if (!exited) {
          child.kill('SIGTERM');
          let timer;
          await Promise.race([exitPromise, new Promise(resolveDone => { timer = setTimeout(resolveDone, 1500); })]);
          clearTimeout(timer);
          if (!exited) {
            child.kill('SIGKILL');
            let killTimer;
            await Promise.race([exitPromise, new Promise(resolveDone => { killTimer = setTimeout(resolveDone, 1500); })]);
            clearTimeout(killTimer);
          }
        }
        await rm(directory, { recursive: true, force: true });
      },
    };
  };
}
