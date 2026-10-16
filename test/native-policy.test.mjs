import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
test('native placement rejects non-restorable origins and positively mismatched identities', { skip: process.platform !== 'darwin' }, async () => {
  const directory = await mkdtemp('/tmp/ym-policy-');
  try {
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-mmacosx-version-min=14.0',
      'tests/PlacementPolicyTests.m', '-framework', 'Foundation', '-framework', 'ApplicationServices', '-o', `${directory}/policy`],
    { env: { ...process.env, DEVELOPER_DIR: process.env.DEVELOPER_DIR || '/Library/Developer/CommandLineTools' } });
    process.stdout.write(execFileSync(`${directory}/policy`));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
