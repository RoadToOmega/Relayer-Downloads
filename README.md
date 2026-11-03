# Relayer Downloads

Bight Audio Relayer installer distribution and upload tools. Application source is maintained separately. Installers belong in GitHub Releases, not Git commits.

## Upload from Windows

1. Double-click **Upload-Windows.cmd** in this folder.
2. Paste or drag your finished `.exe` installer into the window and press Enter.
3. Check the suggested version; press Enter to accept it, or enter the correct version.
4. The uploader creates and verifies a draft release and displays its URL.
5. Press Enter to leave it as a draft. Type **PUBLISH** only when that installer is approved to go live.

The uploader uses Node.js 22 or newer (or the existing Codex Node runtime on Windows) and your existing GitHub login via Git Credential Manager or GitHub CLI. On a new computer, install Node.js and GitHub CLI and run `gh auth login`. Your account needs write access to this repository. Never store tokens in these files.

## Independent platform updates

When you upload Windows, the latest published Mac installer is retained automatically, and vice versa. The first release can contain Windows only. Once Mac is available, run from this folder:

```sh
node Scripts/ReleaseUpload.mjs interactive --platform mac
```

Use a finished `.pkg` file and its actual version. Do not guess the version from an unrelated Windows build.

Only one person should publish at a time. If another release goes live after your draft was created, the uploader rejects that stale draft. Create a fresh draft with a unique tag using `--release` so it retains the newest other-platform installer.

## Stable website links

After a stable release is published, use direct download links on the website:

- Windows: https://github.com/RoadToOmega/Relayer-Downloads/releases/latest/download/Relayer-Windows-Setup.exe
- Mac (after its first published upload): https://github.com/RoadToOmega/Relayer-Downloads/releases/latest/download/Relayer-macOS-Setup.pkg

These links keep working across updates without changing the website. Use normal links rather than a cross-origin JavaScript fetch/rename flow. The uploader now adds versioned files such as Relayer-0.8.67-r2-Windows-Setup.exe and Relayer-0.8.66-r1-macOS-Setup.pkg, plus the fixed-name compatibility copies. The website uses the LatestInstallerUrl.mjs resolver to find the versioned file in the latest stable release; an unavailable/rate-limited lookup falls back to the fixed name. Each platform keeps its own version. The manifest records both filenames, version, size and SHA256. Your local installer is not renamed.

Drafts are not public downloads. Prerelease versions such as `0.9.0-beta.1` do not replace the stable latest download.

## Command-line usage

```sh
node Scripts/ReleaseUpload.mjs status
node Scripts/ReleaseUpload.mjs upload --platform windows --file "path/to/Relayer-0.8.64-windows-x64-vst3-setup-r2.exe" --dry-run
node Scripts/ReleaseUpload.mjs upload --platform windows --file "path/to/installer.exe" --version 0.8.64-r2
node Scripts/ReleaseUpload.mjs publish --release windows-v0.8.64-r2
node --test Tests/ReleaseUpload.Tests.mjs
```

An identical interrupted upload can be retried to resume its draft. Published releases cannot be overwritten by this tool; use a new version/revision. For a fresh draft with the same version, pass a unique `--release` tag to the upload command.

Checks verify file type, size and checksums and preserve the other platform. They do not replace installer testing, signing, notarization or release approval. Publish through this uploader to run its completeness and stale-draft checks.

## Mac launcher

On Mac, pull the latest repository and double-click Scripts/Upload-Mac-Installer.command. If needed, make that launcher executable with chmod +x Scripts/Upload-Mac-Installer.command. Both platforms must use this updated uploader for schema-3 releases. Old published schema-2 releases are read automatically; unfinished old drafts should use a new release tag.


## Install RELAYER companion scripts with ReaPack

Install RELAYER separately, then in REAPER choose **Extensions > ReaPack > Import repositories** and paste:

https://raw.githubusercontent.com/RoadToOmega/Relayer-Downloads/main/index.xml

Choose **Browse packages**, search for **RELAYER Companion Scripts**, install and apply. All five actions and four supporting modules install together. Supporting modules do not appear in the Action List. Use **Synchronize packages** to obtain later updates.

Scripts are proprietary and supplied for use with RELAYER only. See [the script licence](ReaScripts/RELAYER/LICENSE.md) and [usage/compatibility notes](ReaScripts/RELAYER/README.md). Windows REAPER 7.55 and RELAYER 0.8.78 VST3 were tested; other platforms remain unvalidated.

If migrating from a manually extracted ZIP, ReaPack installs into its own managed directory. Reassign existing shortcuts/toolbars to the ReaPack-installed actions before removing old registrations. Future ReaPack updates retain these managed filenames. Do not overwrite ReaPack-managed files with ZIP contents.

## Release companion updates

1. Copy an approved helper bundle into `ReaScripts/RELAYER`, retaining the package descriptor and LICENSE.md. Keep every Lua file together.
2. Increment `@version` in `RELAYER Companion Scripts.lua` and add release notes. Helper versions are separate from plugin versions; never overwrite a published version.
3. Commit and push. The **ReaPack** workflow checks Lua syntax and package metadata and uploads a candidate index artifact.
4. Test the candidate with ReaPack in a disposable REAPER configuration, including fresh install, update and removal.
5. Run the **ReaPack** workflow manually on `main` with **publish** enabled. This updates only `index.xml`. It does not create a GitHub Release, publish an installer or change the website's latest-installer links.

Index downloads point to immutable source commits. Keep historical index entries and those commits available so earlier package versions remain downloadable. Do not amend existing versions. The workflow uses the official reapack-index 1.2.6 tool.
