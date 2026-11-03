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
-- Non-blocking setup window; numeric validation uses the export protocol's limits.
function M.showSetup(done)
  local values={'10','2','2','0.25'}
  local labels={'Variations','Sound length','FX tail','Space between items'}
  local hints={'1–50 files','0.05–60 seconds per variation','0–30 seconds for echoes and reverb','0–30 seconds on the REAPER timeline'}
  local focus,replace,wasDown=1,true,false
  local closed=false
  gfx.init('RELAYER - Export variations',600,460)
  local function close() closed=true;gfx.quit() end
  local function text(s,x,y,size,r,g,b)
    gfx.setfont(1,'Arial',size);gfx.set(r or .9,g or .92,b or .94);gfx.x=x;gfx.y=y;gfx.drawstr(s)
  end
  local function frame()
    local key=gfx.getchar()
    if key<0 or key==27 then close();return end
    if key==9 then focus=focus%4+1;replace=true
    elseif key==8 then values[focus]=replace and '' or values[focus]:sub(1,-2);replace=false
    elseif key>=32 and key<=126 then
      local c=string.char(key)
      if c:match('[%d%.]') and (#values[focus]<10 or replace) then
        values[focus]=replace and c or values[focus]..c;replace=false
      end
    end
    local ok,options=pcall(M.options,table.concat(values,','))
    local down=(gfx.mouse_cap&1)==1;local click=down and not wasDown;wasDown=down
    local w,h=gfx.w,gfx.h
    gfx.set(.08,.09,.10);gfx.rect(0,0,w,h,1)
    if w<560 or h<460 then
      text('Enlarge this window to continue. Esc closes.',20,24,16)
      gfx.update();reaper.defer(frame);return
    end
    text('Export variations',24,22,24)
    text('Render your current patch to a new track at the edit cursor.',24,58,14,.6,.65,.69)
    for i=1,4 do
      local y=100+(i-1)*61
      text(labels[i],24,y,17)
      text(hints[i],24,y+24,13,.6,.65,.69)
      local x=w-154
      if click and gfx.mouse_x>=x and gfx.mouse_x<w-24 and gfx.mouse_y>=y and gfx.mouse_y<y+40 then focus=i;replace=true end
      gfx.set(focus==i and .25 or .16,.23,.25);gfx.rect(x,y,130,40,1)
      text(values[i]..(focus==i and ' |' or ''),x+12,y+10,18)
    end
    if ok then
      local seconds=options.count*(options.duration+options.tail)+(options.count-1)*options.gap
      text(string.format('%d WAV files  ·  %.2f seconds on the timeline',options.count,seconds),24,352,15)
    else
      text(tostring(options):gsub('^.-:%d+: ',''),24,352,15,1,.6,.5)
    end
    text('Includes RELAYER FX. Audio is saved in your project folder.',24,379,13,.6,.65,.69)
    local function button(label,x,width,active)
      gfx.set(active and .77 or .18,active and .92 or .21,active and .33 or .23);gfx.rect(x,h-52,width,32,1)
      text(label,x+12,h-45,15,active and .08 or .8,active and .1 or .82,active and .08 or .84)
      return click and gfx.mouse_x>=x and gfx.mouse_x<x+width and gfx.mouse_y>=h-52 and gfx.mouse_y<h-20
    end
    if button('Cancel',24,90,false) then close();return end
    local submit=button('Export variations',w-196,172,ok)
    if ok and (submit or key==13) then local result=table.concat(values,',');close();done(result);return end
    gfx.update();if not closed then reaper.defer(frame) end
  end
  frame()
end

return M
