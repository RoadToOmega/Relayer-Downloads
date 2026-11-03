-- @noindex
-- REAPER Media Explorer database snapshot writer. No changes to source databases/audio.
local M={version='1.0.0',maxFiles=100000,maxBytes=64*1024*1024}
local function absolute(path)
  return path:match('^%a:[/\\]') or path:match('^[/\\][/\\]') or path:sub(1,1)=='/'
end
local function key(path) return path:gsub('\\','/'):lower() end
local function tokens(line)
  local result={};local i=1
  while i<=#line do
    local _,last=line:find('^%s+',i);if last then i=last+1 end
    if i>#line then break end
    local quote=line:sub(i,i)
    if quote=='"' or quote=="'" or quote=='`' then
      local finish=assert(line:find(quote,i+1,true),'Unclosed database field')
      result[#result+1]=line:sub(i+1,finish-1);i=finish+1
    else
      local finish=line:find('%s',i) or (#line+1)
      result[#result+1]=line:sub(i,finish-1);i=finish
    end
  end
  return result
end
M.tokens=tokens
local function escape(value)
  assert(not value:find('[%z\1-\8\11\12\14-\31]'),'Unsupported control character in database')
  return (value:gsub('&','&amp;'):gsub('"','&quot;'):gsub('<','&lt;'):gsub('>','&gt;')
    :gsub('\r','&#13;'):gsub('\n','&#10;'):gsub('\t','&#9;'))
end
function M.parse(filename,checkpoint)
  local input=assert(io.open(filename,'rb'),'Cannot open database: '..filename)
  local size=input:seek('end');input:seek('set')
  if size>M.maxBytes then input:close();error('Database exceeds 64 MiB limit') end
  local entries,seen={},{};local current;local skipped,duplicates=0,0
  local ok,err=pcall(function()
    local lines=0
    for line in input:lines() do
      lines=lines+1;if checkpoint and lines%256==0 then checkpoint() end
      line=line:gsub('^\239\187\191',''):gsub('\r$','')
      assert(#line<=1024*1024,'Oversized database line')
      local tag=line:match('^(%S+)')
      if tag=='FILE' then
        local t=tokens(line);local path=t[2];current=nil
        assert(path and absolute(path),'Database contains a non-absolute or missing file path')
        if path:lower():match('%.wav$') then
          local k=key(path)
          if seen[k] then current=seen[k];duplicates=duplicates+1
          else
            assert(#entries<M.maxFiles,'Database exceeds 100,000 WAV selections')
            current={path=path,metadata={},seen={}};entries[#entries+1]=current;seen[k]=current
          end
        else skipped=skipped+1 end
      elseif (tag=='DATA' or tag=='USER') and current then
        local t=tokens(line)
        for i=2,#t do
          if not current.seen[t[i]] then current.metadata[#current.metadata+1]=t[i];current.seen[t[i]]=true end
        end
      end
    end
  end)
  input:close();assert(ok,err)
  local cleaned=0
  for index,entry in ipairs(entries) do
    if checkpoint and index%256==0 then checkpoint() end
    entry.metadata=table.concat(entry.metadata,' | ');entry.seen=nil
    -- XML 1.0 cannot represent these embedded metadata separators. Keep words
    -- separated without touching source files or silently changing file paths.
    local count
    entry.metadata,count=entry.metadata:gsub('[%z\1-\8\11\12\14-\31]',' ')
    cleaned=cleaned+count
    assert(#entry.metadata<=65536,'A WAV has more than 64 KiB of database metadata')
  end
  return entries,skipped,duplicates,cleaned
end
function M.xml(source,name,entries,checkpoint)
  assert(absolute(source) and source:lower():match('%.reaperfilelist$'),'Invalid database source')
  assert(name~='' and #name<=1024,'Invalid database name')
  local out={'<?xml version="1.0" encoding="UTF-8"?>\n<RelayerMediaDatabase version="1" source="'..escape(source)..'" name="'..escape(name)..'">'}
  for index,entry in ipairs(entries) do
    if checkpoint and index%256==0 then checkpoint() end
    out[#out+1]='<Wav path="'..escape(entry.path)..'" metadata="'..escape(entry.metadata)..'"/>'
  end
  out[#out+1]='</RelayerMediaDatabase>'
  local xml=table.concat(out,'\n');assert(#xml<=M.maxBytes,'Import snapshot exceeds 64 MiB limit');return xml
end
function M.discover(resource,iniText,enumerate)
  local shortcuts,names={},{};local section
  for line in iniText:gmatch('[^\r\n]+') do
    local heading=line:match('^%[(.-)%]$');if heading then section=heading end
    if section=='reaper_explorer' then
      local i,v=line:match('^Shortcut(%d+)=(.*)$');if i then shortcuts[i]=v end
      i,v=line:match('^ShortcutT(%d+)=(.*)$');if i then names[i]=v end
    end
  end
  local found,seen={},{}
  local function add(path,name)
    if not path:lower():match('%.reaperfilelist$') then return end
    if not absolute(path) then path=resource..'/MediaDB/'..path end
    if seen[key(path)] then return end;seen[key(path)]=true
    found[#found+1]={path=path,name=(name and name~='') and name or path:match('([^/\\]+)%.%w+$')}
  end
  local indexes={};for i in pairs(shortcuts) do indexes[#indexes+1]=tonumber(i) end;table.sort(indexes)
  for _,i in ipairs(indexes) do add(shortcuts[tostring(i)],names[tostring(i)]) end
  local i=0
  while true do local name=enumerate(resource..'/MediaDB',i);if not name then break end;add(name);i=i+1 end
  return found
end
function M.writeRequest(folder,id,xml)
  assert(id:match('^[%w_-]+$'),'Invalid request ID')
  local target=folder..'/'..id..'.request.xml';local temporary=target..'.tmp'
  local file=assert(io.open(temporary,'wb'),'Cannot write import snapshot')
  local ok,err=file:write(xml);local closed,closeError=file:close()
  if not ok or not closed then os.remove(temporary);error(err or closeError) end
  local renamed,why=os.rename(temporary,target)
  if not renamed then os.remove(temporary);error(why) end
  return target
end
return M
