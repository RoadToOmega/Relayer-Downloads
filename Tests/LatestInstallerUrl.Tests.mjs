import test from 'node:test';
import assert from 'node:assert/strict';
import { latestInstallerUrl } from '../Scripts/LatestInstallerUrl.mjs';
const prefix = 'https://github.com/RoadToOmega/Relayer-Downloads/releases/';
test('selects independent versioned assets, never a stable alias or prerelease', async () => {
    const release = { tag_name: 'windows-v0.8.67-r2', assets: ['Relayer-Windows-Setup.exe', 'Relayer-macOS-Setup.pkg', 'Relayer-0.8.67-r2-Windows-Setup.exe', 'Relayer-0.8.66-r1-macOS-Setup.pkg'].map(name => ({ name, state: 'uploaded' })) };
    const request = async () => ({ ok: true, json: async () => release });
    for (const [platform, version, ext] of [['Windows', '0.8.67-r2', 'exe'], ['macOS', '0.8.66-r1', 'pkg']]) {
        const source = prefix + `latest/download/Relayer-${platform}-Setup.${ext}`;
        assert.equal(await latestInstallerUrl(source, request), prefix + `download/windows-v0.8.67-r2/Relayer-${version}-${platform}-Setup.${ext}`);
        release.prerelease = true;
        assert.equal(await latestInstallerUrl(source, request), source);
        release.prerelease = false;
    }
});
test('legacy releases, failed requests and pinned URLs retain their original download', async () => {
    const source = prefix + 'latest/download/Relayer-Windows-Setup.exe';
    for (const request of [async () => ({ ok: false }), async () => { throw Error('offline'); }, async () => ({ ok: true, json: async () => ({ tag_name: 'old', assets: [] }) })]) {
        assert.equal(await latestInstallerUrl(source, request), source);
    }
    const pinned = prefix + 'download/windows-v0.8.64-r2/Relayer-Windows-Setup.exe';
    assert.equal(await latestInstallerUrl(pinned, () => { throw Error('must not request'); }), pinned);
});
