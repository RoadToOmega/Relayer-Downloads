-- @noindex
-- Load one selected WAV into the selected RELAYER layer.
local _,filename=reaper.get_action_context()
local run=dofile(assert(filename:match('^(.*[/\\])'))..'RelayerLoadAction.lua')
run(true)
