-- @noindex
-- Load 1-4 selected WAVs into layers 1-4 in timeline order.
local _,filename=reaper.get_action_context()
local run=dofile(assert(filename:match('^(.*[/\\])'))..'RelayerLoadAction.lua')
run(false)
