import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { macInstallerPath } from '../Scripts/MacInstallerPath.mjs';

test('Mac Terminal drop paths decode safely', () => {
    assert.equal(macInstallerPath('/tmp/My\\ Builds/Relayer.pkg '), '/tmp/My Builds/Relayer.pkg');
    assert.equal(macInstallerPath("'/tmp/My Builds/Relayer.pkg'"), '/tmp/My Builds/Relayer.pkg');
    assert.equal(macInstallerPath('"/tmp/My Builds/Relayer.pkg"'), '/tmp/My Builds/Relayer.pkg');
    assert.equal(macInstallerPath("/tmp/Alec\\'s\\ \\(Mac\\)/Relayer.pkg"), "/tmp/Alec's (Mac)/Relayer.pkg");
    assert.equal(macInstallerPath("'/tmp/Alec'\\''s/Relayer.pkg'"), "/tmp/Alec's/Relayer.pkg");
    assert.equal(macInstallerPath('/tmp/\\$\\(touch\\ nope\\)/Relayer.pkg'), '/tmp/$(touch nope)/Relayer.pkg');
    assert.equal(macInstallerPath('/tmp/音楽/Relayer.pkg'), '/tmp/音楽/Relayer.pkg');
    for (const bad of ['', '/tmp/a.pkg /tmp/b.pkg', "'/tmp/a.pkg", '/tmp/end\\'])
        assert.throws(() => macInstallerPath(bad));
});
test('Literal pasted paths with spaces and punctuation remain intact', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'relayer-path-'));
    try {
        const path = join(dir, "Alec's Mac build.pkg");
        await writeFile(path, 'xar!');
        assert.equal(macInstallerPath(path), path);
    } finally { await rm(dir, { recursive: true, force: true }); }
});
