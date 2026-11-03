# RELAYER REAPER helpers 0.5.2

New: [Import/update Media Explorer databases](MEDIA-EXPLORER.md), retaining database names, curated WAV selections and searchable metadata. Verified against RELAYER 0.8.78; later compatible builds are supported as described below.

New: [Export variations to a new track](EXPORT.md) renders a chosen count from the current patch.

Action: **RELAYER - Load selected WAVs into layers.lua** loads 1-4 WAVs in order. Use the active-layer action to load one WAV into the selected layer.

## Install and use

When updating, replace all helper Lua files together, including `RelayerBridge.lua` and `RelayerExport.lua`. Existing REAPER actions continue working if you replace files in their existing folder.

Keep all Lua files in this directory together. In REAPER open **Actions > Show action list > New action > Load ReaScript**, and select `RELAYER - Load selected WAVs into layers.lua` (not the bridge module).

1. Stop transport.
2. Select 1â€“4 timeline audio items with direct WAV sources.
3. Select exactly one destination track. If it has no RELAYER, the action inserts the installed RELAYER VST3 at the start of its main FX chain. Otherwise it reuses the compatible instance. The selected item can be on another track.
4. Run the action. It fills layers 1â€“4 in timeline order and opens the target plugin. With fewer items, remaining layers keep their current sounds/settings. Equal start times sort by source track order, then item order within the track.

The original WAV is used: item trimming, fades, take FX, pitch and stretch are not rendered. Each replaced layer's source folder, trim, excluded regions, peak overrides and variation weights are reset for its new file. Other layer paths and the patch's controls are retained. Source timeline items are not edited. Multiple matching instances on the selected track are rejected rather than guessed. Selections over four items, MIDI takes, unsupported source types and missing files are rejected before writing any plugin state. The batch uses a single state transfer and Undo entry. FX containers, take FX and Media Explorer remain outside this action.

## Load one WAV into the active layer

Use **RELAYER - Load selected WAV into active layer.lua**. Helpers 0.5.2 remove the misleading legacy layer-1 alias. Reassign any shortcut using that alias to the active-layer action; ReaPack removes the retired file when updating.

1. Install RELAYER 0.8.78 or a later compatible build, then reload the plugin instance.
2. Click the desired layer tab in RELAYER, or use its 1–4 keyboard shortcuts.
3. Stop transport, select exactly one timeline WAV and the track containing that RELAYER instance, then run the action.

Only the selected layer receives the WAV; other layers keep their samples/settings. The last selected layer is retained when the plugin window closes/reopens within the current instance. New instances start on layer 1. Selection is UI state, not automation, and project recall does not restore it. If no plugin exists, the action inserts one and loads its default layer 1. Older builds that cannot report their active layer show an update message without changing samples. The 1–4-WAV action still loads layers 1–4 in order, regardless of the selected tab.

Keep `RelayerLoadAction.lua`, `RelayerBridge.lua` and `RelayerExport.lua` beside all public actions. Do not add these supporting modules to REAPER's Action List. Full-state loading still clears capture history as described below.

## Compatibility and limitations

This uses REAPER's documented `vst_chunk` access and the verified JUCE framing; no new plugin binary, SWS, ReaImGui or network bridge is required. It supports the tested **RELAYER 0.8.78 (state v39)** and **newer builds that retain the same JUCE framing and four-layer state schema**, as well as state v27â€“37. There is no upper state-version cap. Required layer fields and framing are still validated before a write; unknown settings/children and the original state version are preserved. A future breaking format or export protocol change will require a helper update. Product version numbers are not used as a compatibility gate.

It restores the target plugin's full state. That stops/reloads its voices and clears capture history; it is not suitable during playback. REAPER Undo/Redo restores sample paths/settings, not captured audio. Very small parameter round-trip differences exist. REAPER undo also snaps the off-grid EQ Q default from 0.707 to 0.71 (its 0.01 parameter step). The bridge does not introduce this host state behavior but inherits it. A dedicated non-audio load command should replace full-state transfer if transparent live operation is required in pass two.

A successful readback confirms the plugin accepted the path, not that arbitrary WAV decoding succeeded. The plugin's normal worker performs decoding and reports unsupported/corrupt/missing samples. Manually confirm the waveform and audition the source.

## Current verification (2026-11-03)

All nine shipped Lua files compile in REAPER 7.55/x64's Lua 5.4 interpreter on Windows. The exact staged RELAYER 0.8.78 Release VST3 passed the loading and export host suites in a disposable REAPER session:

- One-to-four WAV loading, automatic insertion, legacy single-WAV action, ordering, Unicode paths, Undo/Redo, peer-instance isolation, validation and rollback.
- Export protocol and public export action: actual rendered WAVs, positions/durations, preserved source state, new-track selection, Undo/Redo and failure cleanup.
- 541 compatibility checks, including synthetic future state versions 99/100, unknown-field preservation, all active-layer hints and unsupported-protocol rejection.
- Database parsing and public action queue/cancellation/timeout checks in REAPER's interpreter. The current native plugin library separately passed curated import/update, metadata search, refresh, missing-file recovery, persistence, removal and multi-instance tests. The full Media Explorer dialog-to-live-plugin Library workflow remains a manual check; its native importer tests use isolated storage.
- Native current-build editor checks passed all four active-layer selections, editor reopening and state-restore focus preservation.

Helper 0.5.1 corrects the Library screen name and reports when database receipt polling times out; queued imports remain available for the plugin to process. Replace all Lua files together. No plugin binary change is required.

Product versions are not capped. Future versions must preserve the validated four-layer state layout, JUCE framing, active-layer hint, export protocol 1 and database snapshot protocol 1. Simulated future schemas are regression checks, not proof that an unreleased binary works. Rerun these tests for each release. macOS/Linux and other REAPER versions were not exercised in this pass. See `Docs/ReaperCompanions-0.8.78.md` in the source repository for evidence and remaining manual checks.

## Historical verification

Tested 2026-09-24 in an isolated REAPER 7.55/x64 instance against the existing Release Relayer.vst3, without building the plugin. `Tests/RelayerBridgeTests.lua` passed:

- Two RELAYER instances on one track; the non-target instance remained byte-identical.
- Layer 1 path transfer and preservation of other layer settings (numeric tolerance 0.00001).
- UTF-8, ampersand and percent characters; malformed framing rejection. The original future-version rejection was replaced by compatible-format checks in 0.3.0.
- REAPER Undo/Redo (EQ Q tolerance 0.005 only, for the documented host quantization).
- Public action using a real selected WAV item on a different track from the destination.

Logs and before/after XML are ignored under `Tests/.build`. The integration test refuses any resource directory other than `Tests/.build/reaper-helper` and a non-empty starting project. No DSP, Projucer, parameter or plugin-state-format changes were made for this pass.

## Multi-item pass verification

The expanded isolated REAPER 7.55 host test passed for batches of 1, 2, 3 and 4 WAVs, untouched-layer preservation, missing-file rejection without mutation, timeline ordering through the public action, single Undo/Redo for all four replacements, rejection of five items and untouched peer instances. No plugin build was run. Decoding/listening checks and the full-state-restore limitations above still apply.

## Automatic insertion

Insertion and loading share one Undo entry. Re-running the action reuses the instance. Missing/invalid WAV paths are checked before insertion. An incompatible/offline instance identified as RELAYER is reported instead of silently inserting a duplicate. If insertion or state transfer fails, the newly created instance is removed; existing track effects are retained. RELAYER must already be installed and scanned by REAPER. The script does not install plugins.

Isolated host tests cover insertion, four-layer loading, Undo removal, Redo restoration, repeat-action reuse and missing-plugin error handling.

## 0.2.0 hardening

Keep all files from the same release together; the entry action checks its bridge version. Header validation runs before insertion or state writes, uses bounded reads/chunk counts, and rejects malformed/truncated audio, non-mono/stereo files, unsupported encoding and samples exceeding 600 seconds / 512 MiB decoded. Selected samples exceeding 1 GiB decoded are rejected together. Resident old voices/other layers can still consume additional plugin memory, so this is not a guarantee of decoding success.

Supported preflight formats: little-endian RIFF/WAVE PCM 8/16/24/32-bit or IEEE float 32/64-bit, including their WAVE_FORMAT_EXTENSIBLE forms. RF64/BW64 and compressed WAVs are deliberately rejected with an explanation. No audio conversion is performed.

Offline FX must be brought online before using this helper on their track. This guard runs before any identity/state queries because those queries can wake an offline VST in REAPER. It conservatively applies to any offline FX in the destination's main chain. Renamed instances are detected from their original FX identity and serialized state.

Malformed base64 is rejected. Transfer failures attempt restoration only to the same live FX GUID; failed restoration is explicitly reported. A failed newly inserted instance is removed without touching pre-existing effects.

Expanded isolated REAPER tests passed on 2026-09-25: preflight failures, renamed offline FX, rejected host writes, successful and failed rollback, and failed-insertion cleanup, plus all existing transfer/ordering/undo tests. This helper has limited validation on REAPER 7.55 Windows. A dedicated plugin-side loading protocol, final decode acknowledgement, other REAPER versions/OSes and broader session soak testing remain future work. No plugin rebuild was performed.

## 0.3.0 compatibility verification (2026-10-19)

498 Lua checks passed for current/older states and simulated future states (through v100), unknown-field preservation, four-layer loads, host-write rollback, malformed/incompatible layer rejection and export protocol enforcement. All shipped Lua files passed syntax checks. A saved REAPER state from the current rc.2 r4 VST3 passed path replacement/readback while retaining root settings (including separate-output configuration) and other layer paths.

Run `Tests/RelayerHelperCompatibilityTests.lua` from the repository root using Lua 5.3+. These checks do not replace live REAPER audition/Undo testing; the full live-host suites were not rerun for this script-only update.

## 0.4.0 active-layer verification (2026-10-19)

541 Lua checks passed, including every active destination, missing/invalid selection rejection before writes, public action dispatch, multiple-item rejection and unchanged multi-WAV ordering. Native editor checks passed for default layer 1, all four selections, close/reopen retention and state restoration preserving live focus. Debug/Release Standalone and VST3 built successfully. These are focused native/stub tests; live REAPER audition and Undo tests were not rerun.
