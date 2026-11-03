# Import Media Explorer databases

Use **RELAYER - Import Media Explorer databases.lua** to create or update RELAYER libraries from saved REAPER Media Explorer databases.

## Setup and use

1. Install Windows RELAYER **0.8.78**, or a newer compatible build, then restart REAPER.
2. Extract the complete helper ZIP into your scripts folder. Keep `RelayerMediaDatabase.lua` and `RelayerDatabaseImportUI.lua` beside the action. ReaPack installs these automatically.
3. In **Actions > Show action list > New action > Load ReaScript**, add `RELAYER - Import Media Explorer databases.lua`.
4. Finish saving your database changes in Media Explorer, then run the action.
5. Select databases by name in the importer window, then click **Import selected**. **Select all**, **Clear** and **Refresh** help manage the list. Nothing is selected by default.
6. Open RELAYER's **Library** panel to process the queued imports. Follow each row's status; click a row to see its details. Large databases take time while WAV headers are checked.

The helper imports each saved database's WAV list, not the current search filter or highlighted rows. REAPER display names are retained; unlisted databases use their filename. Files can come from different folders; neighbouring files are not added. Duplicate paths merge their metadata.

Descriptive and custom DATA/USER metadata remains searchable. Audio properties are checked from the WAV itself. The short metadata preview does not limit the stored searchable metadata. XML-incompatible control characters in imported descriptive metadata are replaced with spaces, with a cleanup count shown in the result. File paths remain strictly validated. Audio files and source databases are never copied or modified.

## Updating

Run the helper again to update names, WAV selections and metadata. The same source database path updates the same RELAYER library. Moving or renaming the database file itself creates a separate library. Favourites remain associated with sound paths.

This is a manual snapshot, not continuous syncing. RELAYER's **Refresh** rechecks only the imported WAV list; rerun the helper for changes made in REAPER. Missing/unsupported WAVs remain in the snapshot but are omitted from results; Refresh can recover them when available. An empty database clears its imported results. Existing folder libraries remain unchanged.

## Results and limits

On Windows, requests and receipts are in `%APPDATA%\ABReaLayerNative\Library\ReaperImports`. Completed `.result.xml` files contain success/failure details. The window shows per-database results. After two minutes, **Check again** resumes checking for slower imports. Closing the window keeps already queued requests. Preparation yields regularly so you can cancel before submission. With RELAYER closed, requests wait until its Library opens.

Limits: 32 libraries and 100,000 indexed WAVs across RELAYER; 64 MiB per source database and submitted snapshot batch; 64 KiB metadata per WAV. Invalid/oversized imports keep the previous library. Each selected database commits separately. Existing sound limits apply: mono/stereo, up to 600 seconds and 512 MiB decoded per WAV.

Removing an imported library does not delete its WAVs or REAPER database.

## Verification

Windows Debug/Release builds, isolated native import/update tests, existing library regressions and Lua parser/action checks passed. The parser read the existing 81,669-WAV Boom Library database without modifying it. Live REAPER interaction and macOS/Linux runtime checks have not been rerun for this feature.

2026-11-03: REAPER 7.55/x64 (Lua 5.4) parser/action checks and current 0.8.78 native importer tests passed again. Action dialogs were scripted; native import storage was isolated. Full live-plugin Library interaction remains a manual check.
