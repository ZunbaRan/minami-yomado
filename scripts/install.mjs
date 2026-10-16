#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { WorkspaceClient } from '../mcp/client.mjs';

const source = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
let prefix = path.join(os.homedir(), '.local/share/minami-yomado'), codex = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--codex') codex = true;
  else if (args[i] === '--prefix' && args[i + 1]) prefix = path.resolve(args[++i]);
  else if (args[i] === '--help') {
    console.log('Usage: node scripts/install.mjs [--codex] [--prefix DIRECTORY]\nInstall a built release into a stable location. --codex registers minami_yomado.'); process.exit(0);
  } else throw new Error(`Unknown or incomplete option: ${args[i]}`);
}
function run(command, argv) {
  const result = spawnSync(command, argv, { stdio: 'inherit' });
  if (result.error || result.status !== 0) throw result.error || new Error(`${command} exited ${result.status}`);
}
async function existingService() {
  const client = new WorkspaceClient({ autostart: false, timeout: 3000 });
  let status;
  try { status = await client.request('workspace_list'); }
  catch (error) {
    if (error.beforeSend && ['ENOENT', 'ECONNREFUSED'].includes(error.code)) return;
    throw error;
  }
  if (status.workspaces.some(w => w.running || w.recovery_required))
    throw new Error('A workspace is active. Restore its windows, stop owned workspaces, then run the installer again. Nothing was replaced.');
  // An idle old helper must exit so the next connection uses the new executable.
  await client.request('service_shutdown');
  for (let n = 0; n < 50; n++) {
    await new Promise(r => setTimeout(r, 100));
    try { await client.request('service_status'); }
    catch (error) { if (error.beforeSend && ['ENOENT', 'ECONNREFUSED'].includes(error.code)) return; }
  }
  throw new Error('Previous helper has not exited. Inspect it before retrying installation.');
}

let lock, stage, switchPath;
try {
  if (process.platform !== 'darwin' || Number(process.versions.node.split('.')[0]) < 20)
    throw new Error('Minami Yomado requires macOS and Node.js 20 or newer.');
  const executable = path.join(source, 'dist/Minami Yomado.app/Contents/MacOS/MinamiYomado');
  await fs.access(executable, fs.constants.X_OK);
  await fs.access(path.join(source, 'node_modules/@modelcontextprotocol/sdk/package.json'));
  if (codex) run('codex', ['--version']);
  await existingService();
  await fs.mkdir(prefix, { recursive: true, mode: 0o700 });
  const lockPath = path.join(prefix, '.install-lock');
  await fs.mkdir(lockPath); lock = lockPath;
  const current = path.join(prefix, 'current');
  let oldTarget;
  try {
    const stat = await fs.lstat(current);
    if (!stat.isSymbolicLink()) throw new Error(`${current} is not an installation symlink; refusing to replace it.`);
    oldTarget = await fs.readlink(current);
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const pkg = JSON.parse(await fs.readFile(path.join(source, 'package.json'), 'utf8'));
  const release = path.join(prefix, 'releases', `${pkg.version}-${randomUUID()}`);
  stage = `${release}.staging`; await fs.mkdir(stage, { recursive: true });
  const entries = ['mcp', 'node_modules', 'dist/Minami Yomado.app', 'package.json', 'package-lock.json',
    'scripts/doctor.mjs', 'scripts/install.mjs', 'README.md', 'README.zh-CN.md', 'LICENSE', 'AGENTS.md',
    'docs/quickstart.md', 'docs/mcp-workspaces.md'];
  for (const entry of entries) {
    const target = path.join(stage, entry); await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.cp(path.join(source, entry), target, { recursive: true, verbatimSymlinks: true });
  }
  try { await fs.copyFile(path.join(source, 'release.json'), path.join(stage, 'release.json')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  await fs.rename(stage, release); stage = null;
  switchPath = path.join(prefix, `.current-${randomUUID()}`);
  await fs.symlink(path.relative(prefix, release), switchPath);
  await fs.rename(switchPath, current); switchPath = null;
  const server = path.join(current, 'mcp/server.mjs');
  const configuration = { mcpServers: { minami_yomado: { command: process.execPath, args: [server] } } };
  try {
    if (codex) run('codex', ['mcp', 'add', 'minami_yomado', '--', process.execPath, server]);
    await fs.writeFile(path.join(prefix, 'mcp-config.json'), JSON.stringify(configuration, null, 2) + '\n');
  } catch (error) {
    if (oldTarget) {
      switchPath = path.join(prefix, `.rollback-${randomUUID()}`);
      await fs.symlink(oldTarget, switchPath); await fs.rename(switchPath, current); switchPath = null;
    } else await fs.unlink(current);
    throw error;
  }
  console.log(`\nInstalled Minami Yomado ${pkg.version} at ${current}`);
  console.log(codex ? 'Registered Codex MCP server: minami_yomado. Start a new Codex session.' : 'MCP client configuration:');
  console.log(JSON.stringify(configuration, null, 2));
  console.log(`\nDiagnostic command:\n${JSON.stringify(process.execPath)} ${JSON.stringify(path.join(current, 'scripts/doctor.mjs'))} --connect`);
  console.log('First use: review macOS Accessibility / Device Control and Screen Recording permissions for your host/helper. The installer does not grant permissions or create a display.');
} catch (error) {
  console.error(`Installation failed: ${error.message}`); process.exitCode = 1;
} finally {
  if (switchPath) await fs.unlink(switchPath).catch(() => {});
  if (stage) await fs.rm(stage, { recursive: true, force: true });
  if (lock) await fs.rmdir(lock);
}
