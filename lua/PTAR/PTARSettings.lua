-- Per-server/character runtime preferences (per-zone remembered routes, MQ-console echo, multi-box door role, mode, view).
-- Plain key=value text, atomic saves (same tmp/bak/promote pattern as PTARFiles' route index).
local files=require('PTAR.PTARFiles')
local M={}
-- DL-021: a route is remembered against its stored starting zone exactly as stored. The zone goes in the value,
-- percent-encoded, so no character in a zone name can break the key=value format or silently skip persistence.
local function encode_zone(zone)
  return (zone:gsub('[^A-Za-z0-9_%-]',function(c) return string.format('%%%02X',c:byte()) end))
end
local function decode_zone(text)
  local rest=text:gsub('%%%x%x','')
  if rest:find('%',1,true) then return nil end
  return (text:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end))
end
local function safe(s) return tostring(s or 'unknown'):gsub('[^%w_%-]','_') end
function M.filename(identity)
  local server,char=identity()
  return 'PTAR_Settings_'..safe(server)..'_'..safe(char)..'.txt'
end
function M.path(dir,identity) return dir..'/'..M.filename(identity) end
function M.read(dir,identity)
  local f=io.open(M.path(dir,identity),'r')
  if not f then return {zone_routes={}} end
  local settings={}
  local zone_routes={}
  for line in f:lines() do
    local key,value=line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if key=='zone_route' then
      local encoded,file=value:match('^(%S+) (%S+)$')
      local zone=encoded and decode_zone(encoded)
      if zone and zone~='' and files.accept(file) then zone_routes[zone]=file end
    elseif key then settings[key]=value end
  end
  settings.zone_routes=zone_routes
  f:close()
  settings.last_route=nil   -- DL-021: the legacy single last_route is ignored; per-zone routes replace it
  if settings.echo_enabled=='true' then settings.echo_enabled=true
  elseif settings.echo_enabled=='false' then settings.echo_enabled=false
  else settings.echo_enabled=nil end
  if settings.door_role~='primary' and settings.door_role~='secondary' then settings.door_role=nil end
  if settings.mode~='solo' and settings.mode~='group' then settings.mode=nil end
  if settings.view~='full' and settings.view~='compact' then settings.view=nil end
  -- DL-023: the per-character notice flag is ignored; the shared PTAR_Notice.txt replaced it. Reported so the Runner can
  -- re-save this file once and remove the key.
  if settings.seen_mode_notice~=nil then settings.dropped_notice_flag=true end
  settings.seen_mode_notice=nil
  return settings
end
function M.save(dir,identity,settings)
  local path=M.path(dir,identity)
  local lines={}
  if settings.echo_enabled~=nil then lines[#lines+1]='echo_enabled='..tostring(settings.echo_enabled) end
  if settings.door_role=='primary' or settings.door_role=='secondary' then lines[#lines+1]='door_role='..settings.door_role end
  if settings.mode=='solo' or settings.mode=='group' then lines[#lines+1]='mode='..settings.mode end
  if settings.view=='full' or settings.view=='compact' then lines[#lines+1]='view='..settings.view end
  local zones={}
  for zone,file in pairs(settings.zone_routes or {}) do
    if type(zone)=='string' and zone~='' and files.accept(file) then zones[#zones+1]=zone end
  end
  table.sort(zones)
  for _,zone in ipairs(zones) do lines[#lines+1]='zone_route='..encode_zone(zone)..' '..settings.zone_routes[zone] end
  local f,e=io.open(path..'.tmp','w'); if not f then return nil,e end
  local wrote,we=f:write(table.concat(lines,'\n')..'\n')
  local closed,ce=f:close()
  if not wrote or not closed then return nil,we or ce end
  local old=io.open(path,'r')
  if old then old:close(); os.remove(path..'.bak'); local ok,rename_err=os.rename(path,path..'.bak')
    if not ok then return nil,rename_err end end
  local ok,rename_err=os.rename(path..'.tmp',path)
  if not ok then os.rename(path..'.bak',path); return nil,rename_err end
  return true
end
return M
