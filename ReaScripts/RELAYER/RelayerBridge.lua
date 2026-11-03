-- @noindex
-- RELAYER selected-WAV state bridge. No extensions or plugin rebuild required.
-- Accept state v27+ with the existing JUCE framing and Layer schema.
-- Preserve unknown fields so additive plugin updates need no helper update.
local M = { version = "0.4.0" }
local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function M.decode(s)
  assert(type(s)=='string' and #s<4*1024*1024,'Invalid or oversized FX state')
  s=s:gsub('%s','')
  assert(#s>0 and #s%4==0 and not s:find('[^%w+/=]'),'Invalid base64 FX state')
  local body=s:gsub('=+$','')
  assert(not body:find('=',1,true) and #s-#body<=2,'Invalid base64 padding')
  local out,value,bits={},0,0
  for c in s:gmatch('.') do
    local n=alphabet:find(c,1,true)
    if n then
      value=(value<<6)|(n-1); bits=bits+6
      if bits>=8 then bits=bits-8; out[#out+1]=string.char((value>>bits)&255); value=value&((1<<bits)-1) end
    end
  end
  return table.concat(out)
end
function M.encode(s)
  local out={}
  for i=1,#s,3 do
    local a,b,c=s:byte(i,i+2); local n=(a<<16)|((b or 0)<<8)|(c or 0)
    for shift=18,0,-6 do
      local j=((n>>shift)&63)+1
      out[#out+1]=(shift==6 and not b or shift==0 and not c) and '=' or alphabet:sub(j,j)
    end
  end
  return table.concat(out)
end
function M.unpackState(chunk)
  local raw=M.decode(chunk)
  assert(#raw>=17 and raw:sub(9,12)=='VC2!', 'Unsupported REAPER/JUCE state framing')
  local count=string.unpack('<I4',raw,13)
  assert(count>0 and count<=#raw-16, 'Invalid XML length')
  local xml=raw:sub(17,16+count)
  assert(xml:find('<ABReaLayerNativeState%s') and xml:find('</ABReaLayerNativeState>'), 'This FX is not RELAYER')
  local root=assert(xml:match('<ABReaLayerNativeState%s([^>]+)>'))
  local version=tonumber((' '..root):match('%sversion="(%d+)"'))
  assert(version and version>=27 and version<math.huge,
    'RELAYER state version '..tostring(version)..' is unsupported (requires 27 or newer with compatible state format); instance left untouched')
  return xml,raw,count
end
local function escape(s)
  assert(not s:find('[%z\1-\31]'), 'Invalid control character in WAV path')
  return (s:gsub('&','&amp;'):gsub('"','&quot;'):gsub("'",'&apos;'):gsub('<','&lt;'):gsub('>','&gt;'))
end
local function attribute(tag,key,value)
  local count
  tag,count=tag:gsub('(%s'..key..'=")[^"]*(")',function(a,b) return a..value..b end)
  assert(count==1,'Missing or duplicate layer attribute: '..key)
  return tag
end
function M.replaceLayer(chunk,slot,path)
  assert(type(slot)=='number' and slot%1==0 and slot>=0 and slot<4,'Invalid destination layer')
  assert(type(path)=='string' and path:lower():match('%.wav$'),'Select a WAV source')
  local xml,raw,count=M.unpackState(chunk)
  local position,seen,target=1,{},nil
  while true do
    local a,b=xml:find('<Layer%s[^>]*>',position)
    if not a then break end
    local tag=xml:sub(a,b);local n=tonumber(tag:match('%sslot="(%d+)"'))
    assert(n and n>=0 and n<4 and not seen[n],'Invalid layer slots');seen[n]=true
    local ending=b
    if not tag:match('/>$') then local _,e=xml:find('</Layer>',b+1,true);assert(e,'Missing layer closing tag');ending=e end
    if n==slot then target={a,b,ending,tag} end
    position=ending+1
  end
  for i=0,3 do assert(seen[i],'Missing layer') end
  assert(target,'Missing destination layer')
  local tag=attribute(target[4],'samplePath',escape(path))
  tag=attribute(tag,'sourceFolder','')
  tag=attribute(tag,'TrimStart','0');tag=attribute(tag,'TrimEnd','1')
  local tail=xml:sub(target[2]+1,target[3])
  for _,name in ipairs({'PeakMarker','DisabledRegion','VariationWeight'}) do tail=tail:gsub('<'..name..'%s[^>]*/>','') end
  local changed=xml:sub(1,target[1]-1)..tag..tail..xml:sub(target[3]+1)
  local length=string.unpack('<I4',raw)
  assert(length>=count and length<=#raw,'Invalid VST component length')
  local updated=string.pack('<I4',length+#changed-count)..raw:sub(5,12)..string.pack('<I4',#changed)..changed..raw:sub(17+count)
  return M.encode(updated)
end
function M.layerPath(xml,slot)
  local layer
  for tag in xml:gmatch('<Layer%s[^>]*>') do
    if tonumber(tag:match('%sslot="(%d+)"'))==slot then
      assert(not layer,'Duplicate readback layer');layer=tag
    end
  end
  assert(layer,'Missing readback layer')
  local path=assert(layer:match('%ssamplePath="([^"]*)"'),'Missing readback path')
  local entities={amp='&',quot='"',apos="'",lt='<',gt='>'}
  return (path:gsub('&([^;]+);',function(entity)
    if entities[entity] then return entities[entity] end
    local n=entity:match('^#x(%x+)$')
    if n then return utf8.char(tonumber(n,16)) end
    n=entity:match('^#(%d+)$')
    assert(n,'Unknown XML entity');return utf8.char(tonumber(n))
  end))
end
-- Bounded header preflight; never reads a full sample into Lua memory.
function M.validateWav(path)
  assert(type(path)=='string' and path:lower():match('%.wav$') and not path:find('[%z\1-\31]'),'Invalid WAV path')
  local file=assert(io.open(path,'rb'),'WAV missing or unreadable: '..path)
  local ok,result=pcall(function()
    local size=assert(file:seek('end'));file:seek('set',0)
    local header=file:read(12)
    assert(header and #header==12 and header:sub(1,4)=='RIFF' and header:sub(9,12)=='WAVE',
      'Expected RIFF WAV (RF64/BW64/compressed files are not supported by this helper yet)')
    local limit=string.unpack('<I4',header,5)+8
    assert(limit<=size and limit>=12,'Truncated WAV container')
    local position,format,data=12,nil,nil
    local chunks=0
    while position+8<=limit do
      chunks=chunks+1;assert(chunks<=4096,'Too many WAV metadata chunks')
      file:seek('set',position);local chunk=assert(file:read(8))
      local id,length=chunk:sub(1,4),string.unpack('<I4',chunk,5)
      assert(position+8+length<=limit,'Truncated WAV chunk')
      if id=='fmt ' then
        assert(not format and length>=16,'Invalid WAV format chunk')
        local bytes=assert(file:read(math.min(length,40)))
        local kind,channels,rate,byteRate,align,bits=string.unpack('<I2I2I4I4I2I2',bytes)
        if kind==65534 then
          assert(length>=40 and string.unpack('<I2',bytes,17)>=22,'Invalid extensible WAV header')
          local guid=bytes:sub(25,40)
          assert(guid:sub(5)==string.char(0,0,16,0,128,0,0,170,0,56,155,113),'Unsupported WAV subformat')
          kind=string.unpack('<I4',guid)
        end
        assert((kind==1 and (bits==8 or bits==16 or bits==24 or bits==32)) or (kind==3 and (bits==32 or bits==64)), 'Unsupported WAV encoding')
        assert(channels==1 or channels==2,'WAV must be mono or stereo')
        assert(rate>0 and align==channels*bits/8 and byteRate==rate*align,'Invalid WAV sample format')
        format={channels=channels,rate=rate,align=align}
      elseif id=='data' then
        assert(not data,'Multiple WAV data chunks are unsupported');data=length
      end
      position=position+8+length+(length%2)
    end
    assert(format and data and data>0 and data%format.align==0,'Missing or invalid WAV audio data')
    local frames=data/format.align
    assert(frames/format.rate<=600 and frames*format.channels*4<=512*1024*1024,'WAV exceeds RELAYER 10-minute / 512 MiB decoded limit')
    return {frames=frames,rate=format.rate,channels=format.channels,bytes=frames*format.channels*4}
  end)
  file:close();assert(ok,'WAV validation failed: '..tostring(result)..' ['..path..']')
  return result
end
function M.validatePaths(paths)
  assert(type(paths)=='table' and #paths>=1 and #paths<=4,'Select 1-4 WAV items')
  local total=0
  for _,path in ipairs(paths) do total=total+M.validateWav(path).bytes end
  assert(total<=1024*1024*1024,'Selected WAVs exceed RELAYER 1 GiB sample budget')
end
function M.activeLayer(xml)
  local root=assert(xml:match('<ABReaLayerNativeState%s([^>]+)>'),'Missing RELAYER state')
  local slot=tonumber((' '..root):match('%sreaperActiveLayer="(%d+)"'))
  assert(slot and slot>=0 and slot<4,
    'This RELAYER build does not report its active layer. Install the updated plugin, reload the instance and select a layer; no sound was changed.')
  return slot
end
function M.loadMany(track,fx,paths,externalUndo,useActiveLayer)
  assert(reaper.GetPlayState()==0,'Stop REAPER transport before using this prototype')
  M.validatePaths(paths)
  local guid=reaper.TrackFX_GetFXGUID(track,fx)
  assert(guid and guid~='','Invalid target FX')
  local ok,original=reaper.TrackFX_GetNamedConfigParm(track,fx,'vst_chunk');assert(ok,'Cannot read target FX state')
  local firstSlot=0
  if useActiveLayer then
    assert(#paths==1,'Select exactly one timeline WAV for the active layer')
    firstSlot=M.activeLayer(M.unpackState(original))
  end
  local changed=original
  for i,path in ipairs(paths) do changed=M.replaceLayer(changed,firstSlot+i-1,path) end
  assert(reaper.TrackFX_GetFXGUID(track,fx)==guid,'Target FX changed')
  if not externalUndo then reaper.Undo_BeginBlock2(0) end
  local success,err=pcall(function()
    assert(reaper.TrackFX_SetNamedConfigParm(track,fx,'vst_chunk',changed),'REAPER rejected updated state')
    local readOK,readback=reaper.TrackFX_GetNamedConfigParm(track,fx,'vst_chunk');assert(readOK,'Unable to verify transfer')
    local xml=M.unpackState(readback)
    for i,path in ipairs(paths) do
      assert(M.layerPath(xml,firstSlot+i-1):gsub('\\','/')==path:gsub('\\','/'),'Target layer '..(firstSlot+i)..' did not retain WAV path')
    end
  end)
  if not success then
    local restored=false
    if reaper.ValidatePtr2(0,track,'MediaTrack*') and reaper.TrackFX_GetFXGUID(track,fx)==guid then
      local worked,accepted=pcall(reaper.TrackFX_SetNamedConfigParm,track,fx,'vst_chunk',original)
      restored=worked and accepted
    end
    err=tostring(err)..(restored and '\nPrevious state restored.' or '\nWARNING: rollback could not be confirmed. Check this instance before continuing.')
  end
  if not externalUndo then reaper.Undo_EndBlock2(0,'RELAYER: load '..#paths..' selected WAV(s)',2) end
  assert(success,err)
  return guid
end
function M.load(track,fx,path) return M.loadMany(track,fx,{path}) end
function M.loadActive(track,fx,path,externalUndo) return M.loadMany(track,fx,{path},externalUndo,true) end
return M
