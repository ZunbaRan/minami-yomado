#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { WorkspaceClient } from '../mcp/client.mjs';

const args = process.argv.slice(2);
if (args.includes('--help')) { console.log('Usage: node scripts/doctor.mjs [--connect]\nWithout --connect, inspect installation only. --connect starts/connects to the helper and checks permissions; it never creates a display.'); process.exit(0); }
if (args.some(a => a !== '--connect')) { console.error('Unknown argument; use --help.'); process.exit(1); }
const root = fileURLToPath(new URL('../', import.meta.url));
const report = { ok: true, checks: [] };
async function check(name, action) {
  try { const detail = await action(); report.checks.push({ name, ok: true, detail }); }
  catch (error) { report.ok = false; report.checks.push({ name, ok: false, detail: error.message }); }
}
await check('platform', () => { if (process.platform !== 'darwin') throw Error('Requires macOS.'); return `${process.platform}/${process.arch}`; });
await check('node', () => { if (+process.versions.node.split('.')[0] < 20) throw Error('Install Node.js 20+.'); return process.version; });
await check('MCP dependencies', async () => { await import('@modelcontextprotocol/sdk/server/index.js'); return 'available'; });
await check('native helper', async () => {
  await fs.access(path.join(root, 'dist/Minami Yomado.app/Contents/MacOS/MinamiYomado'), fs.constants.X_OK);
  const r = spawnSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', path.join(root, 'dist/Minami Yomado.app')], { encoding: 'utf8' });
  if (r.error || r.status) throw r.error || Error(r.stderr.trim()); return 'executable; code signature valid (not a notarization check)';
});
if (args.includes('--connect') && report.ok) await check('helper connection and permissions', async () => {
  const status = await new WorkspaceClient().call('service_status');
  if (!status.accessibility || !status.screen_recording) throw Error(`Accessibility/Device Control: ${Boolean(status.accessibility)}; Screen Recording: ${Boolean(status.screen_recording)}. Enable the missing permission for the responsible host/helper in macOS System Settings, then reconnect.`);
  return status;
});
console.log(JSON.stringify(report, null, 2)); process.exitCode = report.ok ? 0 : 1;
