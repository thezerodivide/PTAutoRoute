-- Portable route index. Lua has no standard directory enumeration API.
local data=require('PTAR.PTARRouteData')
local M={}
local INDEX='PTAR_Routes.txt'
function M.filename(input)
  if type(input)~='string' then return nil,'Enter a route filename' end
  local suffix=input:gsub('%.lua$',''):gsub('^PTAR_','')
  if not suffix:match('^[%w_%-]+$') or #suffix>80 then
    return nil,'Use letters, digits, underscores or hyphens (up to 80 characters)'
  end
  return 'PTAR_'..suffix..'.lua'
end
function M.accept(name)
  return type(name)=='string' and (name:match('^PTAR_[%w_%-]+%.lua$') ~= nil or
    name=='SleeperTombRoute_runner_test.lua' or name=='SleeperTombRoute.lua')
end
local function names(dir)
  local f=io.open(dir..'/'..INDEX,'r') or io.open(dir..'/'..INDEX..'.bak','r')
  if not f then return {} end
  local list,seen={},{}
  for line in f:lines() do
    local name=line:match('^%s*(.-)%s*$')
    if M.accept(name) and not seen[name] then seen[name]=true; list[#list+1]=name end
  end
  f:close()
  return list
end
M.names=names
-- True when the route has something to finish on: a Finish waypoint, a Manual handoff, or a finishing door.
function M.has_endpoint(route)
  if type(route)~='table' or type(route.waypoints)~='table' or #route.waypoints==0 then return false end
  for _,w in ipairs(route.waypoints) do
    if w.type=='finish' or w.manual_handoff or w.door_after=='finish_open' or w.door_after=='finish_zone' then return true end
  end
  return false
end
local function readable(text) return type(text)=='string' and text~='' and text or nil end
function M.scan(dir)
  local list={}
  for _,name in ipairs(names(dir)) do
    local route,err=data.read(dir..'/'..name)
    if route then
      local errors=data.validate(route)
      if #errors==0 then
        list[#list+1]={file=name,name=route.route_name,zone=route.zone_short_name,incomplete=not M.has_endpoint(route),
          label=string.format('%s [%s] — %s',route.route_name,route.zone_short_name,name)}
      else err=table.concat(errors,'; ') end
    end
    if err then
      -- DL-021: a route that parsed but failed validation keeps its readable name and zone, so the Runner can
      -- still place it; an unreadable file has neither.
      list[#list+1]={file=name,label=name..' [invalid: '..tostring(err)..']',error=tostring(err),
        name=route and readable(route.route_name) or nil,zone=route and readable(route.zone_short_name) or nil}
    end
  end
  table.sort(list,function(a,b) return a.file:lower()<b.file:lower() end)
  return list
end
-- Write the index atomically: .tmp, then the previous index becomes .bak, then the .tmp is promoted.
local function write_index(dir,list)
  local path=dir..'/'..INDEX
  local f,e=io.open(path..'.tmp','w'); if not f then return nil,e end
  local wrote,we=f:write(table.concat(list,'\n')..'\n')
  local closed,ce=f:close()
  if not wrote or not closed then return nil,we or ce end
  local old=io.open(path,'r')
  if old then old:close(); os.remove(path..'.bak'); local ok,rename_err=os.rename(path,path..'.bak')
    if not ok then return nil,rename_err end end
  local ok,rename_err=os.rename(path..'.tmp',path)
  if not ok then os.rename(path..'.bak',path); return nil,rename_err end
  return true
end
function M.add(dir,name)
  if not M.accept(name) then return nil,'Invalid route filename' end
  local route,err=data.read(dir..'/'..name)
  if not route then return nil,'Could not load route: '..tostring(err) end
  local errors=data.validate(route)
  if #errors>0 then return nil,'Invalid route: '..table.concat(errors,'; ') end
  local list=names(dir)
  for _,existing in ipairs(list) do if existing==name then return true end end
  list[#list+1]=name
  return write_index(dir,list)
end
-- DL-022: take one route's entry out of the index (atomic, same tmp/bak/promote pattern as add). Succeeds when the name was
-- not listed. On failure the index is unchanged.
function M.remove(dir,name)
  local list=names(dir)
  local kept,found={},false
  for _,existing in ipairs(list) do
    if existing==name then found=true else kept[#kept+1]=existing end
  end
  if not found then return true end
  return write_index(dir,kept)
end
-- DL-022: delete a route as one file set: its index entry FIRST (so a failure there deletes nothing), then the route file,
-- then its .bak and .tmp siblings. The path is built only from an accepted PTAR route file name inside `dir`.
-- Result: {ok, name, stage (nil|'name'|'index'|'file'|'sibling'), error, failed_file, index_removed, removed={files}}.
function M.delete_route(dir,name)
  local result={ok=false,name=name,index_removed=false,removed={}}
  if not M.accept(name) then result.stage='name'; return result end
  local ok,err=M.remove(dir,name)
  if not ok then result.stage='index'; result.error=tostring(err); return result end
  result.index_removed=true
  local function present(path) local f=io.open(path,'rb'); if f then f:close(); return true end; return false end
  local function delete(file)
    local path=dir..'/'..file
    if not present(path) then return true end
    local removed,remove_err=os.remove(path)
    if not removed then return false,tostring(remove_err) end
    result.removed[#result.removed+1]=file
    return true
  end
  local deleted,delete_err=delete(name)
  if not deleted then result.stage='file'; result.error=delete_err; return result end
  for _,suffix in ipairs({'.bak','.tmp'}) do
    local sibling=name..suffix
    local sibling_ok,sibling_err=delete(sibling)
    if not sibling_ok and not result.failed_file then
      result.stage='sibling'; result.failed_file=sibling; result.error=sibling_err
    end
  end
  if result.stage then return result end
  result.ok=true
  return result
end
-- The message shown in the Editor for a delete result (developer-approved wording).
function M.delete_message(result)
  local name=tostring(result.name)
  if result.ok then
    return 'Delete confirmed: '..name..' has been deleted. Refresh Routes in the Runner to update its list.'
  end
  if result.stage=='name' then return 'Delete failed: '..name..' is not a PTAR route file name.' end
  if result.stage=='index' then
    return 'Delete failed: '..name..' was not deleted. The route list could not be updated: '..tostring(result.error)
  end
  if result.stage=='file' then
    return 'Delete incomplete: '..name..' was removed from the list, but the file could not be deleted: '..tostring(result.error)
      ..'. Use Register Existing File to restore it.'
  end
  return 'Delete incomplete: '..name..' was deleted, but '..tostring(result.failed_file)..' could not be removed: '
    ..tostring(result.error)..'. Remove it by hand before reusing the name.'
end
-- The Editor log lines for a delete result.
function M.delete_log_lines(result)
  local name=tostring(result.name)
  local lines={}
  if result.stage=='name' then
    lines[1]='Delete route failed: '..name..': not a PTAR route file name'
    return lines
  end
  if result.index_removed then lines[#lines+1]='Delete route: index entry removed' end
  for _,file in ipairs(result.removed or {}) do lines[#lines+1]='Delete route: removed '..file end
  if result.stage=='index' then
    lines[#lines+1]='Delete route failed: '..name..': the route list could not be updated: '..tostring(result.error)
  elseif result.stage=='file' then
    lines[#lines+1]='Delete route failed: '..name..': could not delete the file: '..tostring(result.error)
  elseif result.stage=='sibling' then
    lines[#lines+1]='Delete route failed: '..name..': could not remove '..tostring(result.failed_file)..': '..tostring(result.error)
  end
  return lines
end
return M
