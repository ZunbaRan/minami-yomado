import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
test('preview opening preserves user geometry and clamps to the current physical screen', { skip: process.platform !== 'darwin' }, async () => {
  const directory = await mkdtemp('/tmp/ym-preview-');
  try {
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-mmacosx-version-min=14.0',
      'tests/PreviewGeometryTests.m', '-framework', 'Foundation', '-framework', 'CoreGraphics', '-o', `${directory}/policy`],
    { env: { ...process.env, DEVELOPER_DIR: process.env.DEVELOPER_DIR || '/Library/Developer/CommandLineTools' } });
    process.stdout.write(execFileSync(`${directory}/policy`));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
