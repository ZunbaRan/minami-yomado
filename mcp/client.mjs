import net from 'node:net';
import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
export class WorkspaceClient {
  constructor({ directory = process.env.MINAMI_YOMADO_STATE_DIR || process.env.YOMADO_MCP_STATE_DIR || path.join(os.homedir(), 'Library/Application Support/yomado-mcp'),
    executable = path.join(root, 'dist/Minami Yomado.app/Contents/MacOS/MinamiYomado'), autostart = true, timeout = 120000 } = {}) {
    this.directory = directory; this.executable = executable; this.autostart = autostart; this.timeout = timeout;
    this.socket = path.join(directory, 'service.sock'); this.starting = null;
  }
  async prepare() {
    await fs.mkdir(this.directory, { recursive: true, mode: 0o700 });
    const stat = await fs.lstat(this.directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077))
      throw new Error('State directory must be owned by this user with mode 0700.');
    if (Buffer.byteLength(this.socket) >= 104) throw new Error('State directory produces a socket path longer than macOS supports.');
  }
  request(method, args = {}) {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection(this.socket);
      let bytes = Buffer.alloc(0); let sent = false;
      const timer = setTimeout(() => socket.destroy(new Error(`Timed out during ${method}; outcome may be unknown. Inspect state before retrying.`)), this.timeout);
      socket.on('connect', () => { sent = true; socket.write(JSON.stringify({ method, arguments: args }) + '\n'); });
      socket.on('data', data => {
        bytes = Buffer.concat([bytes, data]);
        if (bytes.length > 4 * 1024 * 1024) { socket.destroy(new Error('Helper response too large')); return; }
        const end = bytes.indexOf(10); if (end < 0) return;
        try {
          const response = JSON.parse(bytes.subarray(0, end).toString());
          if (response.error) reject(Object.assign(new Error(response.error.message), { code: response.error.code }));
          else if ('result' in response) resolve(response.result);
          else reject(new Error('Invalid helper response'));
        } catch (error) { reject(error); }
        socket.end(); clearTimeout(timer);
      });
      socket.on('error', error => { error.beforeSend = !sent; reject(error); });
      socket.on('close', () => { clearTimeout(timer); reject(new Error(`Helper disconnected during ${method}; inspect state before retrying.`)); });
    });
  }
  async ensure() {
    await this.prepare();
    try { return await this.request('service_status'); }
    catch (error) {
      if (!error.beforeSend || !['ENOENT', 'ECONNREFUSED'].includes(error.code) || !this.autostart) throw error;
    }
    if (!this.starting) this.starting = this.start().finally(() => { this.starting = null; });
    return this.starting;
  }
  async start() {
    await fs.access(this.executable, fs.constants.X_OK);
    const log = await fs.open(path.join(this.directory, 'helper.log'), 'a', 0o600);
    let spawnError;
    const child = spawn(this.executable, [this.directory], { detached: true, stdio: ['ignore', log.fd, log.fd] });
    child.once('error', error => { spawnError = error; }); child.unref(); await log.close();
    for (let attempt = 0; attempt < 80; attempt++) {
      if (spawnError) throw spawnError;
      try { return await this.request('service_status'); }
      catch (error) { if (!error.beforeSend || !['ENOENT', 'ECONNREFUSED'].includes(error.code)) throw error; }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error(`Native helper failed to start; inspect ${path.join(this.directory, 'helper.log')}`);
  }
  async call(method, args = {}) {
    await this.ensure();
    // Do not replay a mutation after a transport failure.
    return this.request(method, args);
  }
}
