import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { config, repo, inferVersion, inspectInstaller, uploadInstaller, publishDraft, validateManifest } from '../Scripts/ReleaseUpload.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
function githubMock() {
    const state = { releases: [], latest: null, bytes: new Map(), id: 1, failUploadName: null, calls: [] };
    const api = async (method, path, data, binary) => {
        state.calls.push({ method, path });
        const url = new URL(path, 'https://api.github.com');
        const base = `/repos/${repo}`;
        if (method === 'GET' && path === base) return { private: false, permissions: { push: true }, default_branch: 'main' };
        if (method === 'GET' && path === base + '/releases/latest') return state.latest;
        if (method === 'GET' && url.pathname === base + '/releases') return state.releases;
        if (method === 'POST' && path === base + '/releases') {
            const release = { ...data, id: state.id++, assets: [], html_url: 'https://github.com/' + repo + '/releases/tag/' + data.tag_name };
            state.releases.push(release);
            return release;
        }
        const match = url.pathname.match(/\/releases\/(\d+)(\/assets)?$/);
        assert.ok(match, `${method} ${path}`);
        const release = state.releases.find(r => r.id === Number(match[1]));
        if (method === 'GET' && match[2]) return release.assets;
        if (method === 'PATCH') { Object.assign(release, data); if (data.make_latest === 'true') state.latest = release; return release; }
        if (method === 'POST' && match[2] && binary) {
            const name = url.searchParams.get('name');
            if (state.failUploadName === name) { state.failUploadName = null; throw new Error('Simulated interrupted upload'); }
            const bytes = Buffer.from(await data.arrayBuffer());
            const asset = { id: state.id++, name, size: bytes.length, digest: `sha256:${sha(bytes)}`, state: 'uploaded' };
            release.assets.push(asset); state.bytes.set(asset.id, bytes); return asset;
        }
        throw new Error(`Unexpected ${method} ${path}`);
    };
    api.download = async (asset, file) => {
        const bytes = state.bytes.get(asset.id);
        assert.equal(`sha256:${sha(bytes)}`, asset.digest, 'download integrity');
        await writeFile(file, bytes, { flag: 'wx' });
    };
    return { api, state };
}
async function fixtures(t) {
    const dir = await mkdtemp(join(tmpdir(), 'relayer-test-'));
    t.after(async () => { assert.ok(dir.startsWith(join(tmpdir(), 'relayer-test-'))); await rm(dir, { recursive: true, force: true }); });
    const windows = join(dir, 'Relayer-0.8.64-windows-x64-vst3-setup-r2.exe');
    const mac = join(dir, 'Relayer-0.9.0-macos-universal-setup-r1.pkg');
    await writeFile(windows, Buffer.from('MZwindows fixture'));
    await writeFile(mac, Buffer.from('xar!mac fixture'));
    return { dir, windows, mac, w: await inspectInstaller('windows', windows), m: await inspectInstaller('mac', mac) };
}

test('version inference, file type checks and local files unchanged', async t => {
    const f = await fixtures(t);
    assert.equal(inferVersion(f.windows), '0.8.64-r2');
    assert.equal(inferVersion(f.mac), '0.9.0-r1');
    assert.equal(inferVersion('Relayer-1.0.0-rc.2-windows-setup-r3.exe'), '1.0.0-rc.2-r3');
    assert.throws(() => inferVersion('Relayer-Windows-Setup.exe'));
    await assert.rejects(inspectInstaller('mac', f.windows), /Expected a .pkg/);
    const bad = join(f.dir, 'Relayer-1.0.0-fake.exe'); await writeFile(bad, 'not an installer');
    await assert.rejects(inspectInstaller('windows', bad), /signature/);
    assert.equal(f.w.record.sha256, sha(await readFile(f.windows)));
});
test('Windows first, add Mac, update Windows, then update Mac; exact other-platform carry forward', async t => {
    const f = await fixtures(t); const { api, state } = githubMock();
    await uploadInstaller(api, 'windows', f.w, 'windows-v0.8.64-r2');
    assert.equal(state.latest, null);
    const first = await publishDraft(api, 'windows-v0.8.64-r2');
    assert.deepEqual(Object.keys(first.links), ['windows']);
    await uploadInstaller(api, 'mac', f.m, 'mac-v0.9.0-r1');
    await publishDraft(api, 'mac-v0.9.0-r1');
    const win2 = await inspectInstaller('windows', f.windows, '0.8.65-r2');
    await uploadInstaller(api, 'windows', win2, 'windows-v0.8.65-r2');
    await publishDraft(api, 'windows-v0.8.65-r2');
    let manifestAsset = state.latest.assets.find(a => a.name === 'release-manifest.json');
    let manifest = JSON.parse(state.bytes.get(manifestAsset.id));
    assert.equal(manifest.platforms.mac.version, '0.9.0-r1');
    assert.equal(manifest.platforms.mac.sha256, f.m.record.sha256);
    assert.equal(manifest.platforms.windows.version, '0.8.65-r2');
    const mac2 = await inspectInstaller('mac', f.mac, '0.9.1-r1');
    await uploadInstaller(api, 'mac', mac2, 'mac-v0.9.1-r1');
    await publishDraft(api, 'mac-v0.9.1-r1');
    manifestAsset = state.latest.assets.find(a => a.name === 'release-manifest.json');
    manifest = JSON.parse(state.bytes.get(manifestAsset.id));
    assert.equal(manifest.platforms.windows.version, '0.8.65-r2');
    for (const platform of ['windows', 'mac']) {
        const asset = state.latest.assets.find(a => a.name === config.platforms[platform].asset);
        assert.equal(asset.digest, `sha256:${manifest.platforms[platform].sha256}`);
    }
    assert.equal(state.latest.assets.length, 4);
    assert.equal(sha(await readFile(f.windows)), f.w.record.sha256);
});
test('interrupted upload cannot publish; retry resumes and published versions cannot be overwritten', async t => {
    const f = await fixtures(t); const { api, state } = githubMock();
    state.failUploadName = config.platforms.windows.asset;
    await assert.rejects(uploadInstaller(api, 'windows', f.w, 'retry'), /interrupted/);
    await assert.rejects(publishDraft(api, 'retry'), /Incomplete/);
    await uploadInstaller(api, 'windows', f.w, 'retry');
    assert.equal(state.releases.length, 1);
    assert.equal(state.releases[0].assets.length, 3);
    await publishDraft(api, 'retry');
    await assert.rejects(uploadInstaller(api, 'windows', f.w, 'retry'), /Already published/);
    assert.equal(state.calls.some(c => c.method === 'DELETE'), false);
});
test('stale drafts cannot restore an old other-platform build', async t => {
    const f = await fixtures(t); const { api, state } = githubMock();
    await uploadInstaller(api, 'windows', f.w, 'initial'); await publishDraft(api, 'initial');
    await uploadInstaller(api, 'mac', f.m, 'mac-draft');
    await uploadInstaller(api, 'windows', await inspectInstaller('windows', f.windows, '0.8.65'), 'win-draft');
    await publishDraft(api, 'win-draft');
    await assert.rejects(publishDraft(api, 'mac-draft'), /Another release/);
    await assert.rejects(uploadInstaller(api, 'mac', f.m, 'mac-draft'), /stale/);
    assert.equal(state.latest.tag_name, 'win-draft');
});
test('damaged carried installer and mismatched draft assets are rejected', async t => {
    const f = await fixtures(t); const { api, state } = githubMock();
    await uploadInstaller(api, 'windows', f.w, 'initial'); await publishDraft(api, 'initial');
    state.latest.assets.find(a => a.name === config.platforms.windows.asset).digest = 'sha256:' + '0'.repeat(64);
    await assert.rejects(uploadInstaller(api, 'mac', f.m, 'mac'), /differs from its manifest/);
    assert.equal(state.releases.length, 1);
    assert.throws(() => validateManifest({ schema: 2, product: 'Relayer', repository: repo, baseReleaseId: null, platforms: { linux: f.w.record } }), /Invalid platform/);
});
test('prereleases do not move the live download', async t => {
    const f = await fixtures(t); const { api, state } = githubMock();
    const rc = await inspectInstaller('windows', f.windows, '0.9.0-rc.1');
    await uploadInstaller(api, 'windows', rc, 'windows-v0.9.0-rc.1');
    const result = await publishDraft(api, 'windows-v0.9.0-rc.1');
    assert.equal(result.prerelease, true); assert.equal(state.latest, null);
});
