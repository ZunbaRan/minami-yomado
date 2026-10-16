import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, chmod, access } from 'node:fs/promises';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { WorkspaceClient } from '../mcp/client.mjs';
import { validate } from '../mcp/tools.mjs';

test('validation rejects unknown fields, fractional dimensions and wrong types', () => {
  for (const a of [{ width: 1920.5 }, { width: '1920' }, { hidpi: 1 }, { name: '' }, { force: true }])
    assert.throws(() => validate('workspace_create', a));
  assert.throws(() => validate('workspace_stop', {}));
  assert.throws(() => validate('workspace_get', { workspace_id: null }));
  assert.doesNotThrow(() => validate('workspace_create', { name: 'Agent', width: 1920, height: 1080, hidpi: true }));
});

test('private directory rejects group-readable state', async () => {
  const directory = await mkdtemp('/tmp/ym-perm-');
  try {
    await chmod(directory, 0o755);
    await assert.rejects(new WorkspaceClient({ directory }).ensure(), /0700/);
  } finally { await rm(directory, { recursive: true }); }
});

test('MCP profile lifecycle persists across connections without creating displays', { skip: process.platform !== 'darwin' }, async () => {
  const directory = await mkdtemp('/tmp/ym-test-');
  const native = new WorkspaceClient({ directory });
  let client;
  async function connect() {
    const c = new Client({ name: 'workspace-test', version: '1' });
    await c.connect(new StdioClientTransport({ command: process.execPath, args: ['mcp/server.mjs'], env: { ...process.env, YOMADO_MCP_STATE_DIR: directory } }));
    return c;
  }
  async function call(name, args = {}) {
    const result = await client.callTool({ name, arguments: args });
    assert.ok(!result.isError, JSON.stringify(result));
    return JSON.parse(result.content[0].text);
  }
  try {
    client = await connect();
    const list = await client.listTools(); assert.ok(list.tools.some(t => t.name === 'workspace_configure'));
    // Listing tools does not start the native process or alter displays.
    await assert.rejects(access(`${directory}/service.sock`));
    const original = await call('workspace_list');
    const status = await call('service_status');
    const profile = await call('workspace_create', { name: 'Profile test', width: 1280, height: 720 });
    assert.equal(profile.running, false); assert.equal(profile.display_id, null);
    const configured = await call('workspace_configure', { workspace_id: profile.id, hidpi: true, name: 'Updated' });
    assert.equal(configured.pixel_width, 2560);
    const rejected = await client.callTool({ name: 'workspace_configure', arguments: { workspace_id: profile.id, width: 8192, hidpi: true } });
    assert.equal(rejected.isError, true);
    await client.close(); client = await connect();
    assert.equal((await call('service_status')).pid, status.pid);
    assert.equal((await call('workspace_get', { workspace_id: profile.id })).name, 'Updated');
    assert.deepEqual((await call('workspace_list')).displays, original.displays);
    await call('service_shutdown');
    for (let n = 0; n < 60; n++) {
      try { process.kill(status.pid, 0); } catch { break; }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.equal((await call('workspace_get', { workspace_id: profile.id })).name, 'Updated');
    await call('workspace_destroy', { workspace_id: profile.id });
    assert.deepEqual((await call('workspace_list')).workspaces, []);
  } finally {
    await client?.close();
    await native.call('service_shutdown').catch(() => {});
    await new Promise(resolve => setTimeout(resolve, 1200));
    await rm(directory, { recursive: true, force: true });
  }
});
