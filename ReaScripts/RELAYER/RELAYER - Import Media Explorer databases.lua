-- @noindex
-- Import/update saved Media Explorer databases through RELAYER's built-in UI.
local _,script=reaper.get_action_context()
local folder=assert(script:match('^(.*[/\\])'))
local ok,err=pcall(function()
  local db=dofile(folder..'RelayerMediaDatabase.lua')
  local ui=dofile(folder..'RelayerDatabaseImportUI.lua')
  ui.run(db,reaper,gfx)
end)
if not ok then reaper.MB('Could not open the library importer. Update the complete RELAYER Companion Scripts package.\n\n'..tostring(err),'RELAYER library import',0) end
