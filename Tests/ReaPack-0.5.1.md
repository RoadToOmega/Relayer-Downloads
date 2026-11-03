# ReaPack 0.5.1 publication verification — 2026-11-03

- Public index: https://raw.githubusercontent.com/RoadToOmega/Relayer-Downloads/main/index.xml (HTTP 200).
- Official reapack-index 1.2.6 strict metadata validation and Lua 5.4 syntax checks passed in workflow run 41565829260. Publication committed index e909e83; package sources are pinned to ac83df9e8106114ec27267cdb1e57d4ae5f2ea32.
- Actual ReaPack extension installed the package from the public index in an isolated REAPER 7.55/x64 resource directory. Registry version 0.5.1, 13 owned files, five main-section actions and four unregistered Lua modules verified. All Lua files compile after download; installed contents match source (allowing checkout line endings).
- The nine helper payloads match the previously verified RELAYER 0.8.78 helpers, with only noindex metadata added. Proprietary licence permits personal use/modification with RELAYER; redistribution requires Bight Audio permission.
- Initial CI caught LICENSE.txt being treated as a MIDI-note package and a missing pandoc executable. Licence changed to LICENSE.md; workflow installs pandoc; corrected run passed.
- Installation used ReaPack_AddSetRepository and ReaPack_ProcessQueue in the disposable host, not a mocked downloader. Package ownership/registration was read using ReaPack_GetOwner/GetEntryInfo/EnumOwnedFiles. Local evidence: MultiSamplerPro/Tests/.build/ReaPack-install.log.
- Upgrade/downgrade/uninstall, toolbar migration and Mac installation were not exercised in this initial publication. Do not claim those checks passed. Test them before subsequent public updates; no earlier ReaPack version exists yet.
- User's normal REAPER configuration, installed plugin, installer releases and website were not changed. The disposable REAPER process was closed after verification.
