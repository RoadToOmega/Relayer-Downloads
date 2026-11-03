-- @noindex
-- Requires RELAYER's REAPER export protocol 1 (rebuild/install the updated VST3).
local _,filename=reaper.get_action_context()
local loaded,export=pcall(dofile,assert(filename:match('^(.*[/\\])'))..'RelayerExport.lua')
if not loaded then reaper.MB(tostring(export),'RELAYER export',0);return end
local project,track,fx,guid,original,job,id,options,position
local function sourceExists()
  local found=false;local i=0
  while true do local p=reaper.EnumProjects(i,'');if not p then break end
    if p==project then found=true;break end;i=i+1 end
  return found and reaper.ValidatePtr2(project,track,'MediaTrack*')
    and not reaper.TrackFX_GetOffline(track,fx) and reaper.TrackFX_GetFXGUID(track,fx)==guid
end
local function send(action)
  assert(sourceExists(),'The source project or RELAYER instance changed')
  local attrs={action=action,id=id}
  if action=='start' then
    attrs.directory=job;attrs.count=options.count;attrs.duration=options.duration;attrs.tail=options.tail
    local _,_,bpm=reaper.TimeMap_GetTimeSigAtTime(project,position);attrs.tempo=bpm
    attrs.seed=math.random(1,2147483646)
  end
  assert(reaper.TrackFX_SetNamedConfigParm(track,fx,'vst_chunk',export.command(original,attrs)),
    'REAPER could not deliver the export command')
end
local started,finished=false,false
local ok,err=pcall(function()
  project,filename=reaper.EnumProjects(-1,'')
  assert(filename~='','Save the REAPER project first so rendered audio has a permanent project folder')
  assert(reaper.GetPlayStateEx(project)==0,'Stop transport before exporting')
  assert(reaper.CountSelectedTracks(project)==1,'Select exactly one track containing RELAYER')
  track=reaper.GetSelectedTrack(project,0);fx,original=export.find(track);guid=reaper.TrackFX_GetFXGUID(track,fx)
  local accepted,text=reaper.GetUserInputs('RELAYER - Export variations',4,
    'Variations (1-50),Play duration (seconds),FX tail (seconds),Gap between items (seconds)','10,2,2,0.25')
  if not accepted then return end
  options=export.options(text);position=reaper.GetCursorPositionEx(project)
  id=reaper.genGuid():gsub('[^%x]',''):lower()
  assert(#id==32,'Could not create export job ID')
  job=assert(filename:match('^(.*)[/\\]'))..'/Media/RELAYER Exports/RELAYER-'..id
  assert(reaper.RecursiveCreateDirectory(job,0)~=0,'Cannot create project export folder')
  send('start');started=true
end)
if not ok then reaper.MB(tostring(err),'RELAYER export',0);return end
if not started then return end
local began=reaper.time_precise()
gfx.init('RELAYER export',440,110)
reaper.atexit(function()
  gfx.quit()
  if not finished then pcall(send,'cancel') end
end)
local function update()
  local success,message=pcall(function()
    local key=gfx.getchar()
    if key<0 or key==27 or (gfx.mouse_cap&1~=0 and gfx.mouse_y>=65) then
      pcall(send,'cancel');finished=true;gfx.quit();return
    end
    assert(reaper.EnumProjects(-1,'')==project and sourceExists(),'Source project/instance changed; no items imported. Completed WAVs remain in:\n'..job)
    assert(reaper.time_precise()-began<1800,'Export timed out; check RELAYER licensing, sample loading and disk space')
    local files=export.result(job,id,options.count)
    if files then
      export.import(project,files,position,options.gap)
      finished=true;gfx.quit();return
    end
    gfx.set(0.08,0.10,0.12);gfx.rect(0,0,gfx.w,gfx.h,1)
    gfx.set(0.8,0.9,0.93);gfx.x=16;gfx.y=16
    gfx.drawstr(('Rendering %d variations...  %.0f s'):format(options.count,reaper.time_precise()-began))
    gfx.x=16;gfx.y=40;gfx.drawstr('Current patch + RELAYER output FX. Keep this project open.')
    gfx.x=16;gfx.y=76;gfx.drawstr('Cancel (Esc)');gfx.update()
  end)
  if not success then
    pcall(send,'cancel');finished=true;gfx.quit()
    reaper.MB(tostring(message)..'\n\nAny completed WAVs are kept in:\n'..job,'RELAYER export',0)
  elseif not finished then reaper.defer(update) end
end
update()
