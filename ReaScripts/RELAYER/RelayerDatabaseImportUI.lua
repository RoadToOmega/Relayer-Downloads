-- @noindex
-- No ReaImGui, JS API or SWS dependency. Uses REAPER's built-in gfx window.
local M={}
local function message(err)
  return tostring(err):gsub('^.-:%d+: ','')
end
local function unescape(s)
  return s:gsub('&quot;','"'):gsub('&apos;',"'"):gsub('&lt;','<'):gsub('&gt;','>'):gsub('&amp;','&')
end

function M.new(db,r)
  local s={rows={},phase='select',notice='',focus=1,offset=0,db=db,r=r}
  function s:refresh()
    if self.phase~='select' then return end
    local previous={};for _,row in ipairs(self.rows) do previous[row.path]=row.selected end
    local ok,result=pcall(function()
      local f=assert(io.open(r.get_ini_file(),'rb'),'Cannot read REAPER configuration.')
      local ini=f:read('*a');f:close()
      return db.discover(r.GetResourcePath(),ini,r.EnumerateFiles)
    end)
    if not ok then self.notice=message(result);return end
    self.rows=result;self.offset=0;self.focus=1;self.notice=''
    for _,row in ipairs(self.rows) do row.selected=previous[row.path]==true end
  end
  function s:count()
    local n=0;for _,row in ipairs(self.rows) do if row.selected then n=n+1 end end;return n
  end
  function s:toggle(i)
    if self.phase~='select' or not self.rows[i] then return end
    local row=self.rows[i]
    if not row.selected and self:count()>=32 then self.notice='Select up to 32 databases per import.';return end
    row.selected=not row.selected;self.notice=''
  end
  function s:all(value)
    if self.phase~='select' then return end
    for i,row in ipairs(self.rows) do row.selected=value and i<=32 end
    self.notice=value and #self.rows>32 and 'Selected the first 32. Import remaining databases separately.' or ''
  end
  function s:start()
    if self.phase~='select' or self:count()==0 then return end
    self.phase='preparing';self.cancelled=false;self.notice='Reading selected databases...'
    local chosen={};for _,row in ipairs(self.rows) do
      row.status=nil;row.detail=nil;row.receipt=nil
      if row.selected then chosen[#chosen+1]=row end
    end
    self.job=coroutine.create(function()
      local function checkpoint()
        assert(not self.cancelled,'Import cancelled before submitting remaining requests.')
        coroutine.yield()
        assert(not self.cancelled,'Import cancelled before submitting remaining requests.')
      end
      local osName=r.GetOS();local base
      if osName:match('Win') then base=os.getenv('APPDATA')
      elseif osName:match('OSX') or osName:match('macOS') then base=assert(os.getenv('HOME'))..'/Library'
      else base=os.getenv('XDG_CONFIG_HOME') or (assert(os.getenv('HOME'))..'/.config') end
      assert(base,'Cannot find the RELAYER library folder.')
      self.inbox=base..'/ABReaLayerNative/Library/ReaperImports'
      local pending,total={},0
      -- Validate every snapshot before submitting any. Yield during large parses.
      for i,row in ipairs(chosen) do
        self.current=row;row.status='Reading';self.notice='Reading '..i..' of '..#chosen..': '..row.name
        checkpoint()
        local entries,skipped,duplicates,cleaned=db.parse(row.path,checkpoint)
        local xml=db.xml(row.path,row.name,entries,checkpoint)
        total=total+#xml;assert(total<=db.maxBytes,'Selected snapshots exceed 64 MiB. Select fewer databases.')
        row.status='Ready';row.detail=#entries..' WAVs | '..skipped..' skipped | '..duplicates..' duplicates merged'
        row.cleanup=(cleaned or 0)>0 and (' | '..cleaned..' metadata characters cleaned') or ''
        row.detail=row.detail..row.cleanup
        pending[#pending+1]={row=row,xml=xml}
      end
      checkpoint()
      r.RecursiveCreateDirectory(self.inbox,0)
      for i,item in ipairs(pending) do
        self.current=item.row
        assert(not self.cancelled,'Import cancelled before submitting remaining requests.')
        local id=string.format('%010d-%012d-',os.time(),math.floor(r.time_precise()*1000))..r.genGuid():gsub('[^%w]','')..'-'..i
        item.row.receipt=db.writeRequest(self.inbox,id,item.xml):gsub('%.request%.xml$','.result.xml')
        item.row.status='Queued'
        checkpoint()
      end
      self.phase='waiting';self.deadline=r.time_precise()+120;self.nextPoll=0
      self.notice='Open Library in RELAYER to finish importing. You can leave this window open.'
    end)
  end
  function s:close()
    self.cancelled=true
    if self.job and coroutine.status(self.job)=='suspended' then coroutine.resume(self.job) end
    self.job=nil
  end
  function s:tick()
    if self.phase=='preparing' then
      local untilTime=r.time_precise()+0.006
      repeat
        local ok,err=coroutine.resume(self.job)
        if not ok then
          if self.current and not self.current.receipt then self.current.status='Failed';self.current.detail=message(err) end
          self.phase='failed';self.notice='Import stopped: '..message(err)..' Already queued requests are retained.';self.job=nil;break
        end
        if coroutine.status(self.job)=='dead' then self.job=nil;break end
      until r.time_precise()>=untilTime
    end
    if self.phase~='waiting' or r.time_precise()<(self.nextPoll or 0) then return end
    self.nextPoll=r.time_precise()+0.5
    local waiting,failed=0,0
    for _,row in ipairs(self.rows) do
      if row.receipt and row.status=='Queued' then
        local f=io.open(row.receipt,'rb')
        if f then
          local result=f:read(65537);f:close()
          local success=#result<=65536 and result:match('ok="([^"]+)"')
          if success=='1' or success=='true' then row.status='Imported'
          else row.status='Failed' end
          row.detail=#result<=65536 and unescape(result:match('message="([^"]*)"') or 'Invalid import result.') or 'Import result is too large.'
          row.detail=row.detail..(row.cleanup or '')
        end
      end
      if row.status=='Queued' then waiting=waiting+1 elseif row.status=='Failed' then failed=failed+1 end
    end
    if waiting==0 then
      self.phase='done';self.notice=failed>0 and 'Some databases could not be imported. Select a row to see its result.' or 'Import complete. Your databases are available in RELAYER Library.'
    elseif r.time_precise()>=self.deadline then
      self.phase='timeout';self.notice='Still queued. Open Library in RELAYER, then click Check again. Closing keeps queued requests.'
    end
  end
  s:refresh()
  return s
end

function M.run(db,r,g)
  local s=M.new(db,r)
  g.init('RELAYER - Import Media Explorer databases',740,math.max(430,math.min(650,300+#s.rows*56)),0)
  local closed=false;local wasDown=false;local pressed
  local function close() if not closed then closed=true;s:close();g.quit() end end
  r.atexit(close)
  local function color(c) g.set(c[1],c[2],c[3],1) end
  local ink={0.91,0.92,0.94};local muted={0.60,0.64,0.68};local lime={0.77,0.92,0.33}
  local function text(value,x,y,w,font,c)
    g.setfont(1,'Arial',font or 15);color(c or ink);g.x=x;g.y=y
    g.drawstr(tostring(value):gsub('[\r\n\t]',' '),0,x+math.max(0,w),y+(font or 15)+5)
  end
  local function frame()
    local key=g.getchar()
    if key<0 or key==27 then close();return end
    s:tick()
    local w,h=g.w,g.h
    if w<540 or h<430 then
      g.set(0.09,0.10,0.11,1);g.rect(0,0,w,h,1)
      text('Enlarge this window to continue. Esc closes.',15,20,w-30,16)
      g.update();r.defer(frame);return
    end
    local down=(g.mouse_cap&1)==1;local release=wasDown and not down;local click=down and not wasDown
    local buttons={}
    local function button(id,label,x,y,bw,enabled,action,primary)
      local hover=g.mouse_x>=x and g.mouse_x<x+bw and g.mouse_y>=y and g.mouse_y<y+32
      if enabled and hover and click then pressed=id end
      color(primary and enabled and lime or (hover and enabled and {0.23,0.26,0.29} or {0.16,0.18,0.20}))
      g.rect(x,y,bw,32,1)
      text(label,x+10,y+7,bw-20,15,primary and enabled and {0.08,0.10,0.08} or (enabled and ink or muted))
      if enabled and hover and release and pressed==id then buttons[#buttons+1]=action end
    end
    local rowsTop=134;local rowsBottom=h-166;local visible=math.max(1,math.floor((rowsBottom-rowsTop)/56))
    if key==30064 then s.focus=math.max(1,s.focus-1) elseif key==1685026670 then s.focus=math.min(#s.rows,s.focus+1)
    elseif key==32 then s:toggle(s.focus) elseif key==13 then s:start() end
    if key==30064 or key==1685026670 then s.offset=math.max(0,math.min(s.focus-1,math.max(s.offset,s.focus-visible))) end
    if g.mouse_wheel~=0 then s.offset=s.offset-math.floor(g.mouse_wheel/120);g.mouse_wheel=0 end
    s.offset=math.max(0,math.min(s.offset,math.max(0,#s.rows-visible)))
    g.set(0.09,0.10,0.11,1);g.rect(0,0,w,h,1)
    text('Import Media Explorer databases',22,18,w-44,23)
    text('Choose saved databases to add or update in RELAYER Library.',22,52,w-44,15,muted)
    local selectable=s.phase=='select'
    button('all','Select all',22,86,100,selectable,function() s:all(true) end)
    button('none','Clear',132,86,76,selectable,function() s:all(false) end)
    button('refresh','Refresh list',218,86,116,selectable,function() s:refresh() end)
    text(s:count()..' selected',w-146,95,124,15,muted)
    if #s.rows==0 then
      text('No saved Media Explorer databases found.',32,rowsTop+30,w-64,18)
      text('Create a database in Media Explorer, save it, then click Refresh list.',32,rowsTop+62,w-64,15,muted)
    end
    for i=s.offset+1,math.min(#s.rows,s.offset+visible) do
      local row=s.rows[i];local y=rowsTop+(i-s.offset-1)*56
      local hover=g.mouse_x>=22 and g.mouse_x<w-22 and g.mouse_y>=y and g.mouse_y<y+52
      color(i==s.focus and {0.18,0.22,0.24} or {0.13,0.15,0.17});g.rect(22,y,w-44,52,1)
      if click and hover then pressed='row'..i end
      if release and hover and pressed=='row'..i then
        s.focus=i;s:toggle(i)
        if not selectable and row.detail then s.notice=row.name..': '..row.detail end
      end
      color(row.selected and lime or muted);g.rect(36,y+17,17,17,row.selected and 1 or 0)
      if row.selected then text('x',39,y+15,16,16,{0.08,0.10,0.08}) end
      text(row.name,66,y+7,w-230,17)
      text(row.detail or row.path,66,y+30,w-102,12,muted)
      text(row.status or '',w-145,y+9,106,14,row.status=='Failed' and {1,0.55,0.46} or lime)
    end
    if #s.rows>visible then text((s.offset+1)..'-'..math.min(#s.rows,s.offset+visible)..' of '..#s.rows..' | Scroll for more',22,rowsBottom+1,w-44,12,muted) end
    -- Two clipped lines provide readable feedback without drawing over buttons.
    g.setfont(1,'Arial',14)
    local rest=s.notice~='' and s.notice or 'Audio stays where it is. Only saved database lists and metadata are imported.'
    for line=0,2 do
      local fit=rest
      while #fit>0 and g.measurestr(fit)>w-44 do fit=fit:sub(1,-2) end
      if #fit<#rest then fit=fit:match('^(.*)%s') or fit end
      text(fit,22,h-137+line*18,w-44,14,ink);rest=rest:sub(#fit+1):gsub('^%s+','')
    end
    button('close',s.phase=='preparing' and 'Cancel' or 'Close',22,h-47,94,true,close)
    if selectable then button('import','Import selected',w-192,h-47,170,s:count()>0,function() s:start() end,true)
    elseif s.phase=='timeout' then button('check','Check again',w-172,h-47,150,true,function() s.phase='waiting';s.deadline=r.time_precise()+120;s.nextPoll=0;s.notice='Checking queued imports. Open Library in RELAYER to process them.' end,true)
    elseif s.phase=='done' or s.phase=='failed' then button('back','Back to selection',w-192,h-47,170,true,function() s.phase='select';s.notice='' end)
    else text(s.phase=='preparing' and 'Preparing import...' or 'Waiting for RELAYER...',w-235,h-38,213,15,muted) end
    wasDown=down;if release then pressed=nil end
    g.update()
    for _,action in ipairs(buttons) do action() end
    if not closed then r.defer(function()
      local ok,err=pcall(frame)
      if not ok then close();r.MB('Library importer stopped. Queued imports are retained.\n\n'..message(err),'RELAYER library import',0) end
    end) end
  end
  frame()
  return s
end
return M
