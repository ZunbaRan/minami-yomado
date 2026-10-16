import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
const exec = promisify(execFile);
const mac = { skip: process.platform !== 'darwin' };

test('installer supports spaces, stable MCP paths and repeat installation without starting a helper', mac, async () => {
  const directory = await fs.mkdtemp('/tmp/ym-install-');
  const prefix = path.join(directory, 'Install with spaces');
  const env = { ...process.env, MINAMI_YOMADO_STATE_DIR: path.join(directory, 'state') };
  let client;
  try {
    await exec(process.execPath, ['scripts/install.mjs', '--prefix', prefix], { env });
    const configuration = JSON.parse(await fs.readFile(path.join(prefix, 'mcp-config.json'))).mcpServers.minami_yomado;
    assert.equal(configuration.command, process.execPath);
    assert.equal(configuration.args[0], path.join(prefix, 'current/mcp/server.mjs'));
    const previous = await fs.readlink(path.join(prefix, 'current'));
    const doctor = await exec(process.execPath, [path.join(prefix, 'current/scripts/doctor.mjs')], { env });
    assert.equal(JSON.parse(doctor.stdout).ok, true);
    client = new Client({ name: 'installed-runtime-test', version: '1' });
    await client.connect(new StdioClientTransport({ ...configuration, env }));
    assert.equal((await client.listTools()).tools.length, 16);
    await client.close(); client = null;
    await assert.rejects(fs.access(path.join(env.MINAMI_YOMADO_STATE_DIR, 'service.sock')));
    await exec(process.execPath, ['scripts/install.mjs', '--prefix', prefix], { env });
    assert.notEqual(await fs.readlink(path.join(prefix, 'current')), previous);
    await fs.access(path.join(prefix, previous, 'mcp/server.mjs'));
    await assert.rejects(fs.access(path.join(prefix, '.install-lock')));
  } finally { await client?.close(); await fs.rm(directory, { recursive: true, force: true }); }
});

test('installer refuses an active workspace without changing the installation or requesting shutdown', mac, async () => {
  const directory = await fs.mkdtemp('/tmp/ym-active-');
  const prefix = path.join(directory, 'install');
  const requests = [];
  const server = net.createServer(socket => socket.once('data', data => {
    const request = JSON.parse(data.toString().trim()); requests.push(request.method);
    socket.end(JSON.stringify({ result: { workspaces: [{ running: true }] } }) + '\n');
  }));
  try {
    await new Promise(resolve => server.listen(path.join(directory, 'service.sock'), resolve));
    await assert.rejects(exec(process.execPath, ['scripts/install.mjs', '--prefix', prefix],
      { env: { ...process.env, MINAMI_YOMADO_STATE_DIR: directory } }), /workspace is active/);
    assert.deepEqual(requests, ['workspace_list']);
    await assert.rejects(fs.access(prefix));
  } finally { await new Promise(resolve => server.close(resolve)); await fs.rm(directory, { recursive: true, force: true }); }
});

test('installer will not overwrite an unrelated current directory', mac, async () => {
  const directory = await fs.mkdtemp('/tmp/ym-unowned-');
  try {
    await fs.mkdir(path.join(directory, 'current'));
    await fs.writeFile(path.join(directory, 'current/keep.txt'), 'user data');
    await assert.rejects(exec(process.execPath, ['scripts/install.mjs', '--prefix', directory],
      { env: { ...process.env, MINAMI_YOMADO_STATE_DIR: path.join(directory, 'state') } }), /not an installation symlink/);
    assert.equal(await fs.readFile(path.join(directory, 'current/keep.txt'), 'utf8'), 'user data');
    await assert.rejects(fs.access(path.join(directory, '.install-lock')));
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});
