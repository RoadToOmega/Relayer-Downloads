import { existsSync } from 'node:fs';

// Terminal escapes dropped paths as shell words. Decode one word only; never
// evaluate command substitutions, variables, or any other shell syntax.
export function macInstallerPath(input) {
    const text = input.trim();
    if (!text) throw new Error('Drag one .pkg installer into this window.');
    if (existsSync(text)) return text; // Also accept an ordinary pasted path with spaces.
    let result = '', quote = null;
    for (let i = 0; i < text.length; ++i) {
        const ch = text[i];
        if (quote === "'") {
            if (ch === "'") quote = null;
            else result += ch;
        } else if (ch === '\\' && (quote !== '"' || /["\\$`\n]/.test(text[i + 1] || ''))) {
            if (++i === text.length) throw new Error('Incomplete path. Drag the installer again.');
            result += text[i];
        } else if (quote === '"') {
            if (ch === '"') quote = null;
            else result += ch;
        } else if (ch === "'" || ch === '"') {
            quote = ch;
        } else if (/\s/.test(ch)) {
            throw new Error('Drag one installer at a time.');
        } else result += ch;
    }
    if (quote) throw new Error('Incomplete quoted path. Drag the installer again.');
    return result;
}
