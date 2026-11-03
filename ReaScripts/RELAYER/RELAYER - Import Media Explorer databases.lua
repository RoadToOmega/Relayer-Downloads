-- @noindex
-- Manually snapshot/update Media Explorer databases in RELAYER's global library.
local _,script=reaper.get_action_context()
local module=assert(script:match('^(.*[/\\])'))..'RelayerMediaDatabase.lua'
local loaded,db=pcall(dofile,module)
if not loaded then reaper.MB('Keep RelayerMediaDatabase.lua beside this action.','RELAYER library import',0);return end
local ok,err=pcall(function()
  local resource=reaper.GetResourcePath()
  local ini=assert(io.open(reaper.get_ini_file(),'rb'),'Cannot read REAPER configuration')
  local text=ini:read('*a');ini:close()
  local databases=db.discover(resource,text,reaper.EnumerateFiles)
  assert(#databases>0,'No Media Explorer databases found. Create a database in Media Explorer first.')
  local listing={}
  for i,d in ipairs(databases) do listing[#listing+1]=i..': '..d.name end
  reaper.ShowConsoleMsg('\nRELAYER - Media Explorer databases\n'..table.concat(listing,'\n')..'\n')
  local accepted,selection=reaper.GetUserInputs('Import/update RELAYER libraries',1,'Database numbers (space separated) or ALL:,extrawidth=160','ALL')
  if not accepted then return end
  local chosen,seen={},{}
  if selection:upper():match('^%s*ALL%s*$') then chosen=databases
  else
    assert(selection:match('^%s*%d[%d%s]*$'),'Enter database numbers separated by spaces, or ALL')
    for n in selection:gmatch('%d+') do
      local i=tonumber(n);assert(databases[i],'Unknown database number: '..n)
      if not seen[i] then chosen[#chosen+1]=databases[i];seen[i]=true end
    end
  end
  assert(#chosen>0 and #chosen<=32,'Select between 1 and 32 databases')
  local osName=reaper.GetOS();local base
  if osName:match('Win') then base=os.getenv('APPDATA')
  elseif osName:match('OSX') or osName:match('macOS') then base=assert(os.getenv('HOME'))..'/Library'
  else base=os.getenv('XDG_CONFIG_HOME') or (assert(os.getenv('HOME'))..'/.config') end
  assert(base,'Cannot find the RELAYER library folder')
  local inbox=base..'/ABReaLayerNative/Library/ReaperImports'
  reaper.RecursiveCreateDirectory(inbox,0)
  local summary={};local pending={};local totalBytes=0
  -- Parse/validate the whole selection before submitting any import requests.
  for _,d in ipairs(chosen) do
    local entries,skipped,duplicates=db.parse(d.path)
    local snapshot=db.xml(d.path,d.name,entries)
    totalBytes=totalBytes+#snapshot
    assert(totalBytes<=db.maxBytes,'Selected snapshots exceed 64 MiB. Import fewer databases at a time.')
    pending[#pending+1]={xml=snapshot,name=d.name}
    summary[#summary+1]=d.name..': '..#entries..' WAV selections, '..skipped..' non-WAVs skipped, '..duplicates..' duplicates merged'
  end
  local results={}
  for i,d in ipairs(pending) do
    local id=string.format('%010d-%012d-',os.time(),math.floor(reaper.time_precise()*1000))..reaper.genGuid():gsub('[^%w]','')..'-'..i
    local path=db.writeRequest(inbox,id,d.xml)
    results[#results+1]=path:gsub('%.request%.xml$','.result.xml')
  end
  reaper.ShowConsoleMsg(table.concat(summary,'\n')..'\n')
  reaper.MB('Queued '..#pending..' database import/update(s).\n\nOpen Library in RELAYER to process them. No audio files are copied. Only these database snapshots are updated; this is not continuous syncing.\n\nResults are saved in:\n'..inbox,'RELAYER library import',0)
  local deadline=reaper.time_precise()+120
  local function poll()
    local waiting=false
    for i,path in ipairs(results) do
      if path then
        local f=io.open(path,'rb')
        if f then
          local result=f:read('*a');f:close()
          local message=result:match('message="([^"]*)"') or 'Import result saved: '..path
          message=message:gsub('&quot;','"'):gsub('&lt;','<'):gsub('&gt;','>'):gsub('&amp;','&')
          reaper.ShowConsoleMsg(message..'\n');results[i]=false
        else waiting=true end
      end
    end
    if waiting then
      if reaper.time_precise()<deadline then reaper.defer(poll)
      else reaper.ShowConsoleMsg('RELAYER: still waiting for database import results. Open Library in RELAYER to process queued requests. Requests remain queued; this action has stopped checking. Check the result files in: '..inbox..'\n') end
    end
  end
  reaper.defer(poll)
end)
if not ok then reaper.MB(tostring(err),'RELAYER library import',0) end
