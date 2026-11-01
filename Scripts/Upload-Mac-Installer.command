#!/bin/bash
# Double-click in Finder, then drag a .pkg into the Terminal prompt.
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
node_bin=""
for candidate in "$(command -v node 2>/dev/null)" "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"; do
    if [ -x "$candidate" ] && "$candidate" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' 2>/dev/null; then
        node_bin="$candidate"
        break
    fi
done
result=1
if [ -z "$node_bin" ]; then
    printf '\nNode.js 22 or newer is required. Install it from https://nodejs.org and reopen this launcher.\n'
else
    "$node_bin" "$script_dir/ReleaseUpload.mjs" interactive --platform mac
    result=$?
fi
printf '\nPress Return to close this window.'
read -r ignored
exit "$result"
