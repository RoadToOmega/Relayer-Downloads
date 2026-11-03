-- @noindex
-- Offline batch export protocol 1. Keep RelayerBridge.lua beside this module.
local M = {}
local here=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local bridge=dofile(here..'RelayerBridge.lua')
local function escape(s)
  assert(not s:find('[%z\1-\31]'),'Invalid export path')
  return (s:gsub('&','&amp;'):gsub('"','&quot;'):gsub('<','&lt;'):gsub('>','&gt;'))
end
function M.options(text)
  local a,b,c,d=text:match('^%s*([^,]+),([^,]+),([^,]+),([^,]+)%s*$')
  local n,duration,tail,gap=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  assert(n and n==math.floor(n) and n>=1 and n<=50,'Choose 1-50 variations')
  assert(duration and duration>=.05 and duration<=60,'Duration must be 0.05-60 seconds')
  assert(tail and tail>=0 and tail<=30,'FX tail must be 0-30 seconds')
  assert(gap and gap>=0 and gap<=30,'Spacing must be 0-30 seconds')
  return {count=n,duration=duration,tail=tail,gap=gap}
end
function M.find(track)
  for fx=0,reaper.TrackFX_GetCount(track)-1 do
    assert(not reaper.TrackFX_GetOffline(track,fx),'Bring all FX on this track online first')
  end
  local target,chunk
  for fx=0,reaper.TrackFX_GetCount(track)-1 do
    local yes,data=reaper.TrackFX_GetNamedConfigParm(track,fx,'vst_chunk')
    local valid,xml=false,nil
    if yes then valid,xml=pcall(bridge.unpackState,data) end
    if valid then
      assert(not target,'Select a track with exactly one RELAYER instance')
      target,chunk=fx,data
      assert(xml:match('reaperExportProtocol="1"'),'This RELAYER build needs updating. Rebuild/install the plugin with REAPER export support, then reload the instance.')
    end
  end
  assert(target,'No compatible RELAYER VST3 in the selected track main FX chain')
  assert(reaper.TrackFX_GetEnabled(track,target),'Enable RELAYER before exporting')
  return target,chunk
end
function M.command(chunk,attrs)
  local _,raw,count=bridge.unpackState(chunk)
  local xml='<RelayerReaperExport protocol="1"'
  for _,key in ipairs({'action','id','directory','count','duration','tail','tempo','seed'}) do
    if attrs[key]~=nil then xml=xml..' '..key..'="'..escape(tostring(attrs[key]))..'"' end
  end
  xml=xml..'/>'
  return bridge.encode(string.pack('<I4',string.unpack('<I4',raw)+#xml-count)..raw:sub(5,12)
    ..string.pack('<I4',#xml)..xml..raw:sub(17+count))
end
function M.result(directory,id,count)
  local f=io.open(directory..'/result.txt','rb')
  if not f then return nil end
  local text=f:read(65537);f:close()
  assert(#text<=65536,'Oversized export receipt')
  local lines={};for line in text:gmatch('[^\r\n]+') do lines[#lines+1]=line end
  assert(lines[1]=='RELAYER_EXPORT_1' and lines[2]==id,'Invalid export receipt')
  assert(lines[3]=='ok',lines[4] or 'RELAYER export failed')
  assert(#lines==count+3,'Export returned an incomplete batch')
  local files={}
  local prefix=directory:gsub('\\','/'):lower()..'/'
  for i=4,#lines do
    local path=lines[i];local normal=path:gsub('\\','/')
    assert(normal:lower():sub(1,#prefix)==prefix and not normal:find('/%.%./')
      and not normal:find('/%./'),'Export path escaped its job folder')
    local info=bridge.validateWav(path)
    files[#files+1]={path=path,length=info.frames/info.rate}
  end
  return files
end
function M.import(project,files,position,gap)
  assert(reaper.EnumProjects(-1,'')==project,'Return to the original project before importing')
  assert(reaper.GetPlayStateEx(project)==0,'Stop transport before importing')
  local track
  reaper.Undo_BeginBlock2(project)
  reaper.PreventUIRefresh(1)
  local ok,err=xpcall(function()
    local index=reaper.CountTracks(project)
    reaper.InsertTrackAtIndex(index,true);track=assert(reaper.GetTrack(project,index))
    reaper.GetSetMediaTrackInfo_String(track,'P_NAME','RELAYER - '..#files..' variations',true)
    reaper.SetMediaTrackInfo_Value(track,'D_VOL',1)
    reaper.SetMediaTrackInfo_Value(track,'D_PAN',0)
    reaper.SetMediaTrackInfo_Value(track,'B_MUTE',0)
    reaper.SetMediaTrackInfo_Value(track,'I_SOLO',0)
    reaper.SetMediaTrackInfo_Value(track,'I_RECARM',0)
    for i,file in ipairs(files) do
      local source=assert(reaper.PCM_Source_CreateFromFile(file.path),'Cannot open rendered WAV')
      local item=reaper.AddMediaItemToTrack(track)
      if not item then reaper.PCM_Source_Destroy(source);error('Cannot create audio item') end
      local take=reaper.AddTakeToMediaItem(item)
      if not take then reaper.PCM_Source_Destroy(source);error('Cannot create audio take') end
      reaper.SetMediaItemTake_Source(take,source)
      reaper.GetSetMediaItemTakeInfo_String(take,'P_NAME',('RELAYER variation %03d'):format(i),true)
      reaper.SetMediaItemInfo_Value(item,'D_POSITION',position)
      reaper.SetMediaItemInfo_Value(item,'D_LENGTH',file.length)
      reaper.SetMediaItemInfo_Value(item,'D_FADEINLEN',0)
      reaper.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',0)
      reaper.SetMediaItemInfo_Value(item,'B_LOOPSRC',0)
      position=position+file.length+gap
    end
  end,debug.traceback)
  if not ok and track and reaper.ValidatePtr2(project,track,'MediaTrack*') then reaper.DeleteTrack(track) end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(project,ok and ('RELAYER: import '..#files..' variations') or 'RELAYER: failed import (rolled back)',-1)
  assert(ok,err)
  reaper.SetOnlyTrackSelected(track)
  reaper.TrackList_AdjustWindows(false);reaper.UpdateArrange()
  return track
end
return M
