-- Shared PTAR locations and conservative one-time migration from config root.
local files=require('PTAR.PTARFiles')
local M={}
local function exists(path)
  local f=io.open(path,'rb')
  if f then f:close(); return true end
  return false
end
local function directory(path)
  if type(path)~='string' or path=='' or path:find('["\r\n]') then
    return nil,'Invalid MacroQuest directory: '..tostring(path)
  end
  local sep=package.config:sub(1,1)
  local native=path:gsub('/','\\')
  local command=sep=='\\' and ('if not exist "'..native..'" mkdir "'..native..'"') or
    ("mkdir -p '"..path:gsub("'","'\\''").."'")
  local ok=os.execute(command)
  if ok~=true and ok~=0 then return nil,'Could not create '..path end
  return true
end
local function relocate(source,destination)
  if not exists(source) then return true end
  if exists(destination) then
    return nil,'Both '..source..' and '..destination..' exist. Neither was replaced; resolve this conflict before running PTAR.'
  end
  local ok,err=os.rename(source,destination)
  if not ok then return nil,'Could not move '..source..' to '..destination..': '..tostring(err) end
  return true
end
local function parent(path)
  local clean=path:gsub('[/\\]+$','')
  return clean:match('^(.*)[/\\][^/\\]+$')
end
function M.prepare(config_root,logs_root)
  if type(config_root)~='string' or not parent(config_root) then return nil,'MacroQuest config directory unavailable' end
  local config=config_root:gsub('[/\\]+$','')..'/PTAutorunner'
  local logs=(logs_root and logs_root:gsub('[/\\]+$','') or parent(config_root)..'/logs')..'/PTAutorunner'
  local ok,err=directory(config); if not ok then return nil,err end
  ok,err=directory(logs); if not ok then return nil,err end
  -- The index identifies the user-authored routes. Move each route and its
  -- recovery files before moving the index, so interruption is resumable.
  local names=files.names(config_root)
  for _,name in ipairs(names) do
    for _,suffix in ipairs({'','.bak','.tmp'}) do
      ok,err=relocate(config_root..'/'..name..suffix,config..'/'..name..suffix)
      if not ok then return nil,err end
    end
  end
  -- Preserve both index generations; never overwrite a previously migrated one.
  for _,suffix in ipairs({'','.bak'}) do
    ok,err=relocate(config_root..'/PTAR_Routes.txt'..suffix,config..'/PTAR_Routes.txt'..suffix)
    if not ok then return nil,err end
  end
  return {config=config,logs=logs,old_config=config_root}
end
function M.migrate_logs(paths)
  local root=paths.old_config
  if root:find('["\r\n]') then return nil,'Invalid legacy log directory' end
  local windows=package.config:sub(1,1)=='\\'
  local command=windows and ('dir /b /a-d "'..root:gsub('/','\\')..'\\PTAR_*.log*" 2>NUL') or
    ("find '"..root:gsub("'","'\\''").."' -maxdepth 1 -type f -name 'PTAR_*.log*' -printf '%f\\n'")
  local pipe=io.popen(command,'r')
  if not pipe then return nil,'Could not list old PTAR logs for migration' end
  local conflicts={}
  for name in pipe:lines() do
    if name:match('^PTAR_[%w_%-]+%.log$') or name:match('^PTAR_[%w_%-]+%.log%.old$') then
      local source=root..'/'..name
      local destination=paths.logs..'/'..name
      if exists(destination) then
        conflicts[#conflicts+1]=name -- Never replace either log.
      else
        local ok,err=os.rename(source,destination)
        if not ok then pipe:close(); return nil,'Could not move legacy log '..name..': '..tostring(err) end
      end
    end
  end
  pipe:close()
  return true,conflicts
end
return M
