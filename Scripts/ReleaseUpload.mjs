#!/usr/bin/env node
// Node 22+; upload installers only, never push the private source repository.
import { readFile, stat, open, mkdtemp, rm } from 'node:fs/promises';
import { createReadStream, createWriteStream, openAsBlob } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { basename, extname, resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createInterface } from 'node:readline/promises';
import { macInstallerPath } from './MacInstallerPath.mjs';

export const config = JSON.parse(await readFile(new URL('./ReleaseUpload.config.json', import.meta.url), 'utf8'));
export const repo = `${config.owner}/${config.repository}`;
const root = `/repos/${repo}`;
const manifestName = 'release-manifest.json';
const sumsName = 'SHA256SUMS.txt';
const versionPattern = /^\d+\.\d+\.\d+(?:-(?:rc|beta)\.\d+)?(?:-r\d+)?$/;
const hashBytes = bytes => createHash('sha256').update(bytes).digest('hex');
const jsonBytes = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
export const latestLinks = () => Object.fromEntries(Object.entries(config.platforms).map(([p, v]) => [p, `https://github.com/${repo}/releases/latest/download/${v.asset}`]));
export const versionedAssetName = (platform, version) => `Relayer-${version}-${platform === 'mac' ? 'macOS' : 'Windows'}-Setup${config.platforms[platform].extension}`;

async function removeScratch(dir) {
    const absolute = resolve(dir);
    if (!absolute.startsWith(resolve(tmpdir()) + (process.platform === 'win32' ? '\\' : '/')) || !/^relayer-(upload|verify)-/.test(basename(absolute))) throw new Error('Refusing to remove an unexpected scratch directory.');
    await rm(absolute, { recursive: true, force: true });
}

export function inferVersion(file) {
    const match = basename(file).match(/^Relayer-(\d+\.\d+\.\d+(?:-(?:rc|beta)\.\d+)?)(?:-|\.)/i);
    if (!match) throw new Error('Cannot infer the version. Supply --version explicitly.');
    const revision = basename(file).match(/-r(\d+)\.(exe|pkg)$/i);
    return match[1] + (revision ? `-r${revision[1]}` : '');
}
async function hashFile(file) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(file)) hash.update(chunk);
    return hash.digest('hex');
}
export async function inspectInstaller(platform, file, version) {
    const dest = config.platforms[platform];
    if (!dest) throw new Error('Platform must be windows or mac.');
    if (!file) throw new Error('An installer file is required.');
    version ||= inferVersion(file);
    if (!versionPattern.test(version)) throw new Error('Use a version such as 0.8.64-r2 or 0.8.65-rc.1.');
    const path = resolve(file);
    const info = await stat(path);
    if (!info.isFile() || info.size === 0 || info.size >= 2 ** 31) throw new Error('Installer must be a nonempty file smaller than 2 GiB.');
    if (extname(path).toLowerCase() !== dest.extension) throw new Error(`Expected a ${dest.extension} installer for ${platform}.`);
    const handle = await open(path, 'r');
    try {
        const signature = Buffer.alloc(dest.magic.length / 2);
        await handle.read(signature, 0, signature.length, 0);
        if (signature.toString('hex') !== dest.magic) throw new Error('Installer signature does not match the selected platform.');
    } finally { await handle.close(); }
    return { path, record: { version, originalFilename: basename(path), asset: dest.asset, size: info.size, sha256: await hashFile(path) } };
}

export function getToken() {
    if (process.env.GH_TOKEN || process.env.GITHUB_TOKEN) return process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
    const candidates = ['gh'];
    if (process.platform === 'win32') candidates.push('C:/Program Files/GitHub CLI/gh.exe', join(process.env.LOCALAPPDATA || '', 'Programs/GitHub CLI/gh.exe'), fileURLToPath(new URL('../Tests/.build/github-cli/bin/gh.exe', import.meta.url)));
    for (const executable of candidates) {
        const gh = spawnSync(executable, ['auth', 'token', '--hostname', 'github.com'], { encoding: 'utf8', windowsHide: true });
        if (gh.status === 0 && gh.stdout.trim()) return gh.stdout.trim();
    }
    const git = process.platform === 'win32' ? 'C:/Program Files/Git/cmd/git.exe' : 'git';
    const result = spawnSync(git, ['credential', 'fill'], { input: 'protocol=https\nhost=github.com\n\n', encoding: 'utf8', windowsHide: true, env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never' } });
    const token = result.stdout?.split(/\r?\n/).find(line => line.startsWith('password='))?.slice(9);
    if (result.status === 0 && token) return token;
    throw new Error('GitHub authentication required. Run gh auth login, or supply GH_TOKEN securely in your environment. Never paste tokens into chat or save them in this repository.');
}
export function githubClient(token) {
    const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Relayer-ReleaseUpload' };
    const api = async (method, path, data, binary = false) => {
        if (!path.startsWith('/')) throw new Error('Expected a GitHub API path.');
        const response = await fetch((binary ? 'https://uploads.github.com' : 'https://api.github.com') + path, {
            method, redirect: 'error', signal: AbortSignal.timeout(binary ? 1200000 : 60000),
            headers: { ...headers, ...(data !== undefined ? { 'Content-Type': binary ? 'application/octet-stream' : 'application/json' } : {}) },
            body: data === undefined ? undefined : binary ? data : JSON.stringify(data)
        });
        if (response.status === 404 && method === 'GET') return null;
        if (!response.ok) throw new Error(`GitHub ${method} failed (${response.status}). Check repository access/rate limits; rerun to resume a draft.`);
        return response.status === 204 ? null : response.json();
    };
    api.download = async (asset, output) => {
        if (!Number.isSafeInteger(asset.id)) throw new Error('Invalid asset ID.');
        let response = await fetch(`https://api.github.com${root}/releases/assets/${asset.id}`, { headers: { ...headers, Accept: 'application/octet-stream' }, redirect: 'manual', signal: AbortSignal.timeout(1200000) });
        if (response.status === 302) {
            const location = new URL(response.headers.get('location'));
            if (location.protocol !== 'https:' || !location.hostname.endsWith('.githubusercontent.com')) throw new Error('Unexpected asset download destination.');
            // Never forward the GitHub token to the signed asset URL.
            response = await fetch(location, { redirect: 'error', signal: AbortSignal.timeout(1200000) });
        }
        if (!response.ok || !response.body) throw new Error('Could not download the release asset.');
        await pipeline(Readable.fromWeb(response.body), createWriteStream(output, { flags: 'wx' }));
        if ((await stat(output)).size !== asset.size || `sha256:${await hashFile(output)}` !== asset.digest) throw new Error(`Downloaded checksum mismatch: ${asset.name}`);
    };
    return api;
}
async function requireRepository(api) {
    const repository = await api('GET', root);
    if (!repository || repository.private || repository.archived || !repository.permissions?.push) throw new Error(`Expected a writable public download repository: ${repo}. Run setup first.`);
    return repository;
}
async function findRelease(api, tag) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,180}$/.test(tag || '')) throw new Error('Invalid release tag.');
    for (let page = 1; ; page++) {
        const releases = await api('GET', `${root}/releases?per_page=100&page=${page}`);
        if (!Array.isArray(releases)) throw new Error('Could not list releases.');
        const match = releases.find(release => release.tag_name === tag);
        if (match) return match;
        if (releases.length < 100) return null;
    }
}
function matches(asset, size, sha256) {
    return asset?.state === 'uploaded' && asset.size === size && asset.digest === `sha256:${sha256}`;
}
export function validateManifest(manifest) {
    if (![2, 3].includes(manifest.schema) || manifest.product !== 'Relayer' || manifest.repository !== repo || !manifest.platforms || !('baseReleaseId' in manifest) || (manifest.baseReleaseId !== null && !Number.isSafeInteger(manifest.baseReleaseId))) throw new Error('Invalid release manifest.');
    const platforms = Object.keys(manifest.platforms);
    if (!platforms.length || platforms.some(p => !config.platforms[p])) throw new Error('Invalid platform records.');
    for (const platform of platforms) {
        const p = manifest.platforms[platform];
        if (!p || !versionPattern.test(p.version) || p.asset !== config.platforms[platform].asset || !Number.isSafeInteger(p.size) || p.size <= 0 || p.size >= 2 ** 31 || !/^[a-f0-9]{64}$/.test(p.sha256) || typeof p.originalFilename !== 'string' || /[\r\n/\\]/.test(p.originalFilename)) throw new Error(`Invalid ${platform} manifest record.`);
        if (manifest.schema === 3 && p.versionedAsset !== versionedAssetName(platform, p.version)) throw new Error(`Invalid ${platform} versioned filename.`);
    }
    return manifest;
}
async function loadManifest(api, release, dir) {
    const assets = await api('GET', `${root}/releases/${release.id}/assets?per_page=100`);
    if (!Array.isArray(assets)) throw new Error('Could not list assets.');
    const asset = assets.find(a => a.name === manifestName);
    if (!asset || asset.size > 65536 || asset.state !== 'uploaded' || !/^sha256:[a-f0-9]{64}$/.test(asset.digest || '')) throw new Error('Release has no valid manifest. Do not mix manual releases with uploader releases.');
    const path = join(dir, `manifest-${release.id}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`);
    await api.download(asset, path);
    return { manifest: validateManifest(JSON.parse(await readFile(path, 'utf8'))), assets };
}
function expectedAssets(manifest) {
    const metadata = jsonBytes(manifest);
    const installers = Object.entries(manifest.platforms).flatMap(([platform, r]) =>
        [r.asset, ...(manifest.schema === 3 ? [r.versionedAsset] : [])].map(name => ({ name, size: r.size, sha256: r.sha256, platform })));
    const sums = Buffer.from(installers.map(p => `${p.sha256}  ${p.name}\n`).join(''));
    return [
        { name: manifestName, size: metadata.length, sha256: hashBytes(metadata), bytes: metadata },
        ...installers,
        { name: sumsName, size: sums.length, sha256: hashBytes(sums), bytes: sums }
    ];
}
export async function uploadInstaller(api, platform, installer, tag, notes = '') {
    if (!config.platforms[platform]) throw new Error('Invalid platform.');
    const repository = await requireRepository(api);
    const dir = await mkdtemp(join(tmpdir(), 'relayer-upload-'));
    try {
        let release = await findRelease(api, tag);
        if (release && !release.draft) throw new Error('Already published. Use a new version/revision; published assets are never overwritten.');
        const latest = await api('GET', `${root}/releases/latest`);
        let base, baseAssets = [];
        if (latest) ({ manifest: base, assets: baseAssets } = await loadManifest(api, latest, dir));
        const platforms = {};
        for (const p of Object.keys(config.platforms)) {
            const record = p === platform ? installer.record : base?.platforms[p];
            if (record) platforms[p] = { ...record, versionedAsset: versionedAssetName(p, record.version) };
        }
        const manifest = validateManifest({ schema: 3, product: 'Relayer', repository: repo, baseReleaseId: latest?.id ?? null, platforms });
        const expected = expectedAssets(manifest);
        const assets = release ? await api('GET', `${root}/releases/${release.id}/assets?per_page=100`) : [];
        if (assets.some(a => !expected.some(e => e.name === a.name))) throw new Error('Unexpected draft assets. Review the draft manually.');
        for (const item of expected) {
            const asset = assets.find(a => a.name === item.name);
            if (asset && !matches(asset, item.size, item.sha256)) throw new Error(`Draft differs or is stale: ${item.name}. Use a new release tag; nothing was overwritten.`);
        }
        const files = { [platform]: installer.path };
        for (const [p, record] of Object.entries(platforms)) {
            if (p === platform || expected.filter(e => e.platform === p).every(e => assets.some(a => a.name === e.name && matches(a, e.size, e.sha256)))) continue;
            const source = baseAssets.find(a => a.name === record.asset);
            if (!matches(source, record.size, record.sha256)) throw new Error(`Current ${p} installer differs from its manifest.`);
            files[p] = join(dir, record.asset);
            await api.download(source, files[p]);
        }
        if (!release) release = await api('POST', `${root}/releases`, {
            tag_name: tag, target_commitish: repository.default_branch,
            name: `Relayer — ${Object.entries(platforms).map(([p, r]) => `${p === 'mac' ? 'macOS' : 'Windows'} ${r.version}`).join(' / ')}`,
            draft: true, prerelease: Object.values(platforms).some(p => /-(rc|beta)\./.test(p.version)),
            body: `${notes.trim() || 'Relayer installer downloads.'}\n\n${Object.entries(platforms).map(([p, r]) => `${p}: ${r.version}`).join('\n')}\n\nSHA-256 checksums are included. Platform versions are tracked independently.`
        });
        if (!release?.id) throw new Error('Could not create draft.');
        for (const item of expected) {
            if (assets.some(a => a.name === item.name)) continue;
            const body = item.bytes ? new Blob([item.bytes]) : await openAsBlob(files[item.platform]);
            const uploaded = await api('POST', `${root}/releases/${release.id}/assets?name=${encodeURIComponent(item.name)}`, body, true);
            if (!matches(uploaded, item.size, item.sha256)) throw new Error(`Verification failed: ${item.name}. Draft remains unpublished; rerun to resume.`);
        }
        return { tag, draft: true, url: release.html_url, versions: Object.fromEntries(Object.entries(platforms).map(([p, r]) => [p, r.version])) };
    } finally { await removeScratch(dir); }
}
export async function publishDraft(api, tag) {
    await requireRepository(api);
    const release = await findRelease(api, tag);
    if (!release?.draft) throw new Error('Expected an existing draft release.');
    const dir = await mkdtemp(join(tmpdir(), 'relayer-verify-'));
    try {
        const { manifest, assets } = await loadManifest(api, release, dir);
        const expected = expectedAssets(manifest);
        if (assets.length !== expected.length || expected.some(e => !matches(assets.find(a => a.name === e.name), e.size, e.sha256))) throw new Error('Incomplete or mismatched draft. Upload again before publishing.');
        const latest = await api('GET', `${root}/releases/latest`);
        if ((latest?.id ?? null) !== manifest.baseReleaseId) throw new Error('Another release became live after this draft was prepared. Prepare a fresh draft to preserve the latest other-platform installer.');
        const prerelease = Object.values(manifest.platforms).some(p => /-(rc|beta)\./.test(p.version));
        const result = await api('PATCH', `${root}/releases/${release.id}`, { draft: false, prerelease, make_latest: prerelease ? 'false' : 'true' });
        if (!result || result.draft) throw new Error('Publish did not complete. Check GitHub before retrying.');
        return { url: result.html_url, prerelease, links: prerelease ? {} : Object.fromEntries(Object.keys(manifest.platforms).map(p => [p, latestLinks()[p]])) };
    } finally { await removeScratch(dir); }
}
export async function setup(api) {
    const user = await api('GET', '/user');
    if (!await api('GET', root)) await api('POST', user.login.toLowerCase() === config.owner.toLowerCase() ? '/user/repos' : `/orgs/${config.owner}/repos`, {
        name: config.repository, description: 'Bight Audio Relayer installers for Windows and macOS. Distribution only; no application source code.', private: false, auto_init: true, has_issues: false, has_projects: false, has_wiki: false
    });
    await requireRepository(api);
    return { repository: `https://github.com/${repo}`, links: latestLinks() };
}
export async function main(argv) {
    const [command, ...rest] = argv;
    const options = {};
    for (let i = 0; i < rest.length; i++) {
        const key = rest[i];
        if (!['--platform', '--file', '--version', '--notes', '--dry-run', '--release'].includes(key) || options[key] !== undefined) throw new Error(`Unknown/repeated argument: ${key}`);
        options[key] = key === '--dry-run' ? true : rest[++i];
        if (options[key] === undefined || (typeof options[key] === 'string' && options[key].startsWith('--'))) throw new Error(`Missing value for ${key}`);
    }
    if (!command || command === 'help') {
        console.log('node Scripts/ReleaseUpload.mjs setup|status\nnode Scripts/ReleaseUpload.mjs upload --platform windows|mac --file <installer> [--version <version>] [--release <unique-tag>] [--notes <file>] [--dry-run]\nnode Scripts/ReleaseUpload.mjs publish --release <draft-tag>\nUploads create drafts and retain the other live platform. Only publish changes live downloads. Run publishers one at a time.');
        return;
    }
    if (command === 'interactive') {
        const platform = options['--platform'] || 'windows';
        if (!config.platforms[platform]) throw new Error('Invalid platform.');
        const rl = createInterface({ input: process.stdin, output: process.stdout });
        try {
            console.log(`Relayer ${platform} uploader — ${repo}\nThe other live platform will be retained automatically.`);
            const input = await rl.question('Paste or drag the installer path here, then press Enter: ');
            const file = platform === 'mac' ? macInstallerPath(input) : input.trim().replace(/^"(.*)"$/, '$1');
            let guessed = '';
            try { guessed = inferVersion(file); } catch {}
            const version = (await rl.question(`Version${guessed ? ` [${guessed}]` : ''}: `)).trim() || guessed;
            const installer = await inspectInstaller(platform, file, version);
            const tag = `${platform}-v${installer.record.version}`;
            console.log(JSON.stringify(installer.record, null, 2));
            const api = githubClient(getToken());
            console.log(JSON.stringify(await uploadInstaller(api, platform, installer, tag), null, 2));
            console.log('Draft uploaded and verified. Publishing makes this installer publicly downloadable.');
            if ((await rl.question('Type PUBLISH to make it live, or press Enter to keep the draft: ')).trim() === 'PUBLISH') console.log(JSON.stringify(await publishDraft(api, tag), null, 2));
        } finally { rl.close(); }
        return;
    }
    if (!['setup', 'status', 'upload', 'publish'].includes(command)) throw new Error('Unknown command. Run help.');
    let installer, tag;
    if (command === 'upload') {
        installer = await inspectInstaller(options['--platform'], options['--file'], options['--version']);
        tag = options['--release'] || `${options['--platform']}-v${installer.record.version}`;
        console.log(JSON.stringify({ repository: repo, tag, ...installer.record }, null, 2));
        if (options['--dry-run']) return;
    } else if (options['--dry-run']) throw new Error('--dry-run is only supported for upload.');
    const api = githubClient(getToken());
    if (command === 'setup') console.log(JSON.stringify(await setup(api), null, 2));
    else if (command === 'status') {
        const user = await api('GET', '/user');
        const repository = await api('GET', root);
        const latest = repository && await api('GET', `${root}/releases/latest`);
        console.log(JSON.stringify({ user: user.login, repository: repo, exists: !!repository, latest: latest?.tag_name || null, links: latestLinks() }, null, 2));
    } else if (command === 'publish') console.log(JSON.stringify(await publishDraft(api, options['--release']), null, 2));
    else {
        const notes = options['--notes'] ? await readFile(options['--notes'], 'utf8') : '';
        console.log(JSON.stringify(await uploadInstaller(api, options['--platform'], installer, tag, notes), null, 2));
    }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
