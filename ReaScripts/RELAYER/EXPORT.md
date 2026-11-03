# Export variations to a new REAPER track

Load **RELAYER - Export variations to new track.lua** into REAPER's Action List.
Keep `RelayerExport.lua` and `RelayerBridge.lua` beside it. This action requires
RELAYER with the export capability (verified with 0.8.78), and later compatible builds containing **REAPER export protocol 1**; unsupported binaries
give an update message instead of changing the instance.

1. Save your REAPER project and stop transport.
2. Select one track containing exactly one enabled RELAYER in its main FX chain.
3. Set the edit cursor where the exported items should begin.
4. Run the action and choose **variation count (1–50)**, **play duration**,
   **FX tail**, and **gap between items**, all times in seconds.
5. The action adds a unity-gain track with one audio item per WAV. One Undo removes
   the imported track; Redo restores it. WAVs remain on disk.

The native offline renderer snapshots the current patch, waits for its sample
loads/stretch to finish, then makes separate stereo float32 WAVs at the plugin's
current sample rate. RELAYER's layer processing, master gain, limiter and output
FX are included. Each render uses a new random seed and the equivalent of the
plugin's Play button. It does not reroll source WAVs or base controls; patches
without random variation can produce identical files. Muted layers, disabled
regions, trigger probability and licensing retain their normal behavior.

Play duration is 0.05–60 seconds. At its end, voices/sequencers stop with a safety
fade; output effects continue for the selected 0–30-second tail. The last 10 ms
fade prevents a hard cut. Allow enough time for long samples and effects.
Session tempo is captured at the edit cursor (quarter-note BPM), not a moving
tempo map. Track/master FX outside RELAYER, track faders, DAW automation and live
MIDI/mod-wheel performance are not baked in. Normal project master processing
still applies when listening to the imported track.

Files live under **<project folder>/Media/RELAYER Exports/RELAYER-<job ID>/** in a
unique batch subfolder, alongside render settings. Do not delete that folder while
the project references its WAVs. The live source patch and history are not restored
or cleared by export. A second processor temporarily consumes additional CPU/RAM.

Escape, the Cancel control or closing the progress window cancels the batch
without importing partial results. Already completed files remain on disk.
Switching/closing the project or removing the source instance prevents import;
failed imports remove only their newly created track. Keep transport stopped until
import finishes. Disk errors, missing samples and licensing failures are reported.
Receipts are correlated to a unique job and validated before import; a 30-minute
timeout cancels an unresponsive job. Take FX, containers and ambiguous instances
are not supported by this first export action.

## Verification

2026-09-25: Debug/Release Standalone and VST3 builds passed with zero warnings or
errors. Focused native production-tools tests passed (export receipt, tempo,
live-state preservation, duplicate/invalid requests, deterministic audio and
cancellation). Isolated REAPER 7.55 tests cover separate randomized WAVs, exact
item positions/durations, source state preservation, import Undo/Redo, retained
files, injected import failure cleanup and cancellation commands. The public action
also passed with scripted dialog answers: four WAVs imported at the original edit
cursor and the new track selected. Rendered samples were finite and non-silent.

Manual checks remaining: listening with your patches, real Cancel/window-close
interaction, large batches with long reverb tails, disk-full scenarios and project
portability. No installer or production DAW session was modified.

2026-11-03: both REAPER host export suites passed again with the exact staged 0.8.78 Release VST3, including the public action with scripted dialog answers. The current plugin preserves a 1 GiB free-space reserve for export; insufficient space is reported through the export result.
