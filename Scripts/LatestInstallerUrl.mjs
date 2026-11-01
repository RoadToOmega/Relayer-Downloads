// Shared reference for the Framer download resolver. No token is required.
export async function latestInstallerUrl(source, request = fetch) {
    const prefix = 'https://github.com/RoadToOmega/Relayer-Downloads/releases/';
    const names = {
        'Relayer-Windows-Setup.exe': /^Relayer-\d+\.\d+\.\d+(?:-r\d+)?-Windows-Setup\.exe$/,
        'Relayer-macOS-Setup.pkg': /^Relayer-\d+\.\d+\.\d+(?:-r\d+)?-macOS-Setup\.pkg$/,
    };
    const name = source.startsWith(prefix + 'latest/download/') ? source.slice((prefix + 'latest/download/').length) : '';
    if (!names[name]) return source;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
        const response = await request('https://api.github.com/repos/RoadToOmega/Relayer-Downloads/releases/latest', { credentials: 'omit', signal: controller.signal });
        if (!response.ok) return source;
        const release = await response.json();
        if (release.draft || release.prerelease || typeof release.tag_name !== 'string' || !Array.isArray(release.assets)) return source;
        const assets = release.assets.filter(a => a.state === 'uploaded' && names[name].test(a.name));
        if (assets.length !== 1) return source;
        return prefix + 'download/' + encodeURIComponent(release.tag_name) + '/' + encodeURIComponent(assets[0].name);
    } catch {
        // Legacy releases, rate limits and network failures keep downloads working.
        return source;
    } finally {
        clearTimeout(timer);
    }
}
