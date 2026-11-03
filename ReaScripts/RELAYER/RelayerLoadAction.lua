-- @noindex
-- Shared selected-WAV action. Keep beside the public action files.
return function(active)
local _,filename=reaper.get_action_context()
local loaded,bridge=pcall(dofile,assert(filename:match('^(.*[/\\])'))..'RelayerBridge.lua')
if not loaded or type(bridge)~='table' or bridge.version~='0.4.0' then
  reaper.MB('Keep the matching RelayerBridge.lua beside this action. Reinstall all helper files together.','RELAYER helper',0)
  return
end
local ok,err=pcall(function()
  assert(reaper.GetPlayState()==0,'Stop playback first. This prototype restores plugin state and clears its capture history.')
  assert(reaper.CountSelectedTracks(0)==1,'Select exactly one destination track')
  local count=reaper.CountSelectedMediaItems(0)
  if active then assert(count==1,'Select exactly one timeline WAV to load into the active layer') end
  assert(count>=1 and count<=4,'Select 1–4 timeline WAV items. More than four will not be truncated.')
  local track=reaper.GetSelectedTrack(0,0)
  local items={}
  for i=0,count-1 do
    local item=reaper.GetSelectedMediaItem(0,i)
    local take=reaper.GetActiveTake(item)
    assert(take and not reaper.TakeIsMIDI(take),'Selected item '..(i+1)..' is not an audio take; no layers changed')
    local source=reaper.GetMediaItemTake_Source(take)
    assert(reaper.GetMediaSourceType(source,'')=='WAVE','Select direct WAV sources; section/reversed sources are not supported')
    items[#items+1]={path=reaper.GetMediaSourceFileName(source,''),
      position=reaper.GetMediaItemInfo_Value(item,'D_POSITION'),
      track=reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(item),'IP_TRACKNUMBER'),
      index=reaper.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER')}
  end
  table.sort(items,function(a,b)
    if a.position~=b.position then return a.position<b.position end
    if a.track~=b.track then return a.track<b.track end
    return a.index<b.index
  end)
  local paths={}
  for i,item in ipairs(items) do
    assert(item.path:lower():match('%.wav$') and reaper.file_exists(item.path),'WAV '..i..' is missing or unsupported; no FX inserted')
    paths[i]=item.path
  end
  bridge.validatePaths(paths)
  local target
  local diagnostics={}
  local incompatibleRelayer=false
  -- Even identity queries can wake an offline VST in REAPER. Do not inspect it.
  for fx=0,reaper.TrackFX_GetCount(track)-1 do
    assert(not reaper.TrackFX_GetOffline(track,fx),'The selected track contains an offline FX. Bring it online or choose another track; no plugin was changed.')
  end
  for fx=0,reaper.TrackFX_GetCount(track)-1 do
    local _,name=reaper.TrackFX_GetFXName(track,fx,'')
    local _,ident=reaper.TrackFX_GetNamedConfigParm(track,fx,'fx_ident')
    local isRelayer=((name or '')..' '..(ident or '')):lower():find('relayer',1,true)~=nil
    assert(not (isRelayer and reaper.TrackFX_GetOffline(track,fx)),'RELAYER is offline. Bring it online before loading WAVs.')
    local yes,chunk=false,nil
    if not reaper.TrackFX_GetOffline(track,fx) then yes,chunk=reaper.TrackFX_GetNamedConfigParm(track,fx,'vst_chunk') end
    local supported,reason=false,'REAPER could not read VST state (check that the FX is online and is the VST3 version)'
    if yes then supported,reason=pcall(bridge.unpackState,chunk) end
    if supported then
      assert(not target,'Multiple RELAYER instances on this track. This action requires exactly one.')
      target=fx
    else
      if isRelayer or tostring(reason):find('RELAYER state version',1,true) then incompatibleRelayer=true end
      diagnostics[#diagnostics+1]=(name or ('FX '..(fx+1)))..': '..tostring(reason)
    end
  end
  local function loadInto(t,f,externalUndo)
    if active then bridge.loadActive(t,f,paths[1],externalUndo) else bridge.loadMany(t,f,paths,externalUndo) end
  end
  if target then
    loadInto(track,target)
  else
    assert(not incompatibleRelayer,'RELAYER is present but unavailable or incompatible. No duplicate was inserted.\n'..table.concat(diagnostics,'\n'))
    reaper.Undo_BeginBlock2(0)
    local inserted,guid
    local success,reason=pcall(function()
      -- Place the instrument before existing track effects. REAPER resolves its installed VST3.
      inserted=reaper.TrackFX_AddByName(track,'VST3: Relayer.vst3',false,-1000)
      assert(inserted and inserted>=0,'RELAYER VST3 is not available. Install/scan it in REAPER Preferences > Plug-ins > VST, then try again.')
      guid=reaper.TrackFX_GetFXGUID(track,inserted)
      loadInto(track,inserted,true)
      target=inserted
    end)
    if not success and inserted and inserted>=0 and reaper.TrackFX_GetFXGUID(track,inserted)==guid then
      reaper.TrackFX_Delete(track,inserted)
    end
    reaper.Undo_EndBlock2(0,'RELAYER: insert and load '..#paths..' selected WAV(s)',2)
    assert(success,reason)
  end
  reaper.TrackFX_Show(track,target,3)
end)
if not ok then reaper.MB(tostring(err),'RELAYER helper',0) end

end
