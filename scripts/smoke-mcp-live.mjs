// Opt-in integration test. Creates only its own two native fixture windows and
// virtual display, verifies restoration, then removes them. Requires macOS GUI
// login plus Screen Recording and Accessibility permission for the test host.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { WorkspaceClient } from '../mcp/client.mjs';

const directory = await mkdtemp('/tmp/ym-live-');
const native = new WorkspaceClient({ directory });
const client = new Client({ name: 'workspace-live-test', version: '1' });
let fixture, workspaceID, failed = false;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function call(name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  if (result.isError) throw new Error(JSON.stringify(result));
  return JSON.parse(result.content[0].text);
}
try {
  execFileSync('xcrun', ['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-mmacosx-version-min=14.0',
    'tests/WorkspaceFixture.m', '-framework', 'AppKit', '-o', `${directory}/fixture`],
  { env: { ...process.env, DEVELOPER_DIR: process.env.DEVELOPER_DIR || '/Library/Developer/CommandLineTools' } });
  await client.connect(new StdioClientTransport({ command: process.execPath, args: ['mcp/server.mjs'],
    env: { ...process.env, MINAMI_YOMADO_STATE_DIR: directory } }));
  const permissions = await call('service_status');
  assert.ok(permissions.accessibility && permissions.screen_recording, 'Grant capture/control permission to the test host first.');
  const before = (await call('workspace_list')).displays;
  fixture = spawn(`${directory}/fixture`, [], { stdio: 'ignore' });
  let windows = [], previousGeometry, stableSamples = 0;
  const windowDeadline = Date.now() + 10000;
  while (Date.now() < windowDeadline) {
    if (fixture.exitCode !== null || fixture.signalCode !== null) throw new Error(`Fixture exited before becoming ready: ${fixture.exitCode ?? fixture.signalCode}`);
    windows = (await call('window_list')).windows.filter(w => w.pid === fixture.pid);
    const geometry = JSON.stringify(windows.map(w => [w.window_id, w.bounds]));
    stableSamples = windows.length === 2 && geometry === previousGeometry ? stableSamples + 1 : 0;
    previousGeometry = geometry;
    // AppKit animates new windows through slightly inset frames before settling.
    if (stableSamples >= 3) break;
    await delay(100);
  }
  assert.equal(windows.length, 2, 'Both native fixture windows must become visible before placement.');
  assert.ok(stableSamples >= 3, 'Fixture window geometry must settle before recording restoration bounds.');
  const profile = await call('workspace_create', { name: 'MCP integration test', width: 1920, height: 1080 }); workspaceID = profile.id;
  const args = { workspace_id: workspaceID };
  const started = await call('workspace_start', args); assert.equal(started.running, true);
  const afterStart = (await call('workspace_list')).displays;
  for (const output of before) assert.deepEqual(afterStart.find(d => d.displayID === output.displayID), output);
  for (const [index, w] of windows.entries()) {
    const moved = await call('workspace_move_window', { ...args, pid: w.pid, window_id: w.window_id, x: 100 + 800*index, y: 180 });
    assert.equal(moved.bounds.x, started.bounds.x + 100 + 800*index);
  }
  const occupied = await client.callTool({ name: 'workspace_stop', arguments: args }); assert.equal(occupied.isError, true);
  const modeChange = await client.callTool({ name: 'workspace_configure', arguments: { ...args, hidpi: true } }); assert.equal(modeChange.isError, true);
  const opened = await call('preview_open', { ...args, fps: 15 });
  assert.equal(opened.bounds.width, 480); assert.equal(opened.bounds.height, 300);
  const reused = await call('preview_open', { ...args, width: 900, height: 600 });
  assert.equal(reused.window_id, opened.window_id, 'Repeated opens reuse the same viewer');
  assert.deepEqual(reused.bounds, opened.bounds, 'Repeated opens never resize the viewer');
  await delay(2200);
  const first = (await call('workspace_get', args)).preview; assert.equal(first.state, 'live'); assert.ok(first.frames > 0);
  await delay(1200); assert.ok((await call('workspace_get', args)).preview.frames > first.frames);
  await call('preview_configure', { ...args, width: 480, height: 300 });
  // Exercise AppKit's real user-geometry notification path, not just configure.
  execFileSync('osascript', ['-e', `tell application "System Events" to tell (first application process whose unix id is ${permissions.pid}) to set size of (first window whose name is "Minami Yomado — MCP integration test") to {400, 260}`]);
  const resized = (await call('workspace_get', args)).preview;
  assert.equal(resized.bounds.width, 400); assert.equal(resized.bounds.height, 260);
  await call('preview_close', args);
  const reopened = await call('preview_open', { ...args, width: 900, height: 600 });
  assert.deepEqual(reopened.bounds, resized.bounds, 'Reopen ignores stale dimensions and restores manual resize');
  await call('preview_close', args); assert.equal((await call('workspace_get', args)).running, true);
  await call('workspace_restore', args);
  const restored = (await call('window_list')).windows;
  for (const w of windows) assert.deepEqual(restored.find(r => r.window_id === w.window_id).bounds, w.bounds);
  await call('workspace_stop', args);
  await call('service_shutdown'); await delay(1600);
  await call('workspace_configure', { ...args, width: 1280, height: 720, hidpi: true });
  assert.equal((await call('workspace_start', args)).pixel_width, 2560);
  const restarted = await call('preview_open', { ...args, fps: 15 });
  assert.deepEqual(restarted.bounds, resized.bounds, 'User geometry survives helper and display restart');
  await delay(1500);
  assert.equal((await call('workspace_get', args)).preview.state, 'live');
  await call('workspace_stop', args); await call('workspace_destroy', args); workspaceID = null;
  assert.deepEqual((await call('workspace_list')).displays, before);
  console.log('PASS: MCP lifecycle, exact restoration, live frames, compact PiP, idempotent open, manual-resize persistence across reopen/helper restart, HiDPI and unchanged physical displays.');
} catch (error) { failed = true; console.error(error); process.exitCode = 1; }
finally {
  // A failing test retains the owned display if restoration cannot be verified.
  if (workspaceID) {
    try {
      await native.call('workspace_restore', { workspace_id: workspaceID });
      await native.call('workspace_stop', { workspace_id: workspaceID });
      await native.call('workspace_destroy', { workspace_id: workspaceID }); workspaceID = null;
    } catch (error) { console.error(`Recovery pending in ${directory}: ${error.message}`); }
  }
  if (fixture && !workspaceID) fixture.kill();
  await client.close();
  if (!workspaceID) {
    await native.call('service_shutdown').catch(() => {}); await delay(1200);
    await rm(directory, { recursive: true, force: true });
  }
  if (failed) process.exitCode = 1;
}
