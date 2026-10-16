#!/usr/bin/env node
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const root = fileURLToPath(new URL('../', import.meta.url));
if (process.platform !== 'darwin' || process.arch !== 'arm64') throw Error('Publishable prebuilt releases must be built on macOS arm64.');
const pkg = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'));
const version = pkg.version;
const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'minami-release-'));
const stage = path.join(temporary, 'minami-yomado');
const output = path.join(root, 'dist', `minami-yomado-${version}-macos-arm64.zip`);
try {
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  if (execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim()) throw Error('Commit release source before packaging.');
  // Build exactly this revision without replacing an active local helper bundle.
  const build = path.join(temporary, 'build');
  execFileSync('bash', ['scripts/build-mcp.sh'], { cwd: root, stdio: 'inherit', env: { ...process.env, MINAMI_YOMADO_BUILD_DIR: build } });
  await fs.mkdir(stage);
  for (const entry of ['mcp', 'dist/Minami Yomado.app', 'scripts/install.sh', 'scripts/install.mjs', 'scripts/doctor.mjs',
    'README.md', 'README.zh-CN.md', 'LICENSE', 'AGENTS.md', 'package.json', 'package-lock.json', 'docs/quickstart.md', 'docs/mcp-workspaces.md']) {
    const destination = path.join(stage, entry); await fs.mkdir(path.dirname(destination), { recursive: true });
    const source = entry === 'dist/Minami Yomado.app' ? path.join(build, 'Minami Yomado.app') : path.join(root, entry);
    await fs.cp(source, destination, { recursive: true, verbatimSymlinks: true });
  }
  execFileSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], { cwd: stage, stdio: 'inherit' });
  execFileSync('codesign', ['--verify', '--deep', '--strict', path.join(stage, 'dist/Minami Yomado.app')]);
  const architecture = execFileSync('lipo', ['-archs', path.join(stage, 'dist/Minami Yomado.app/Contents/MacOS/MinamiYomado')], { encoding: 'utf8' }).trim();
  if (architecture !== 'arm64') throw Error(`Unexpected helper architecture: ${architecture}`);
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(path.join(stage, 'release.json'), JSON.stringify({ name: pkg.name, version, revision, architecture,
    deploymentTarget: '14.0', testedOn: execFileSync('sw_vers', ['-productVersion'], { encoding: 'utf8' }).trim(),
    signing: 'ad-hoc', notarized: false, node: '>=20' }, null, 2) + '\n');
  await fs.rm(output, { force: true });
  execFileSync('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', stage, output]);
  const hash = createHash('sha256').update(await fs.readFile(output)).digest('hex');
  await fs.writeFile(path.join(root, 'dist/SHA256SUMS'), `${hash}  ${path.basename(output)}\n`);
  await fs.copyFile(path.join(root, 'scripts/install.sh'), path.join(root, 'dist/install.sh'));
  console.log(`Packaged ${output}\nSHA-256: ${hash}`);
} finally { await fs.rm(temporary, { recursive: true, force: true }); }
