-- DL-023: the Group-beta notice is acknowledged once per computer per major.minor version. One small shared file in the
-- PTAR config folder holds the flag and the full version string of the build that showed the notice. MQ-free.
local M={}
local FILE='PTAR_Notice.txt'
function M.path(dir) return dir..'/'..FILE end
-- Major and minor as numbers (1.10 is higher than 1.9). The patch number and any -test.N suffix are ignored.
local function major_minor(version)
  local major,minor=tostring(version):match('^(%d+)%.(%d+)')
  if not major then return nil end
  return tonumber(major),tonumber(minor)
end
-- {state='missing'|'malformed'|'ok', version=<string when ok>}. A file that cannot be opened counts as missing.
function M.read(dir)
  local f=io.open(M.path(dir),'r')
  if not f then return {state='missing'} end
  local seen,version
  for line in f:lines() do
    local key,value=line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if key=='mode_notice_seen' then seen=value elseif key=='mode_notice_version' then version=value end
  end
  f:close()
  if seen=='true' and version and major_minor(version) then return {state='ok',version=version} end
  return {state='malformed'}
end
-- Returns show (boolean) and the reason, which names the file state and the versions compared (for the log).
-- Only a higher major or minor than the recorded one shows the notice again; a lower one (a downgrade) does not.
function M.decide(record,current)
  if record.state=='missing' then return true,'shared notice file missing or unreadable' end
  if record.state~='ok' then return true,'shared notice file malformed' end
  local cur_major,cur_minor=major_minor(current)
  if not cur_major then return true,'running version '..tostring(current)..' unreadable' end
  local rec_major,rec_minor=major_minor(record.version)
  local higher=cur_major>rec_major or (cur_major==rec_major and cur_minor>rec_minor)
  local compared='acknowledged at '..record.version..', running '..tostring(current)
  if higher then return true,'newer major.minor than acknowledged ('..compared..')' end
  return false,'already acknowledged ('..compared..')'
end
-- Atomic like the other files: .tmp, the previous file becomes .bak, then the .tmp is promoted.
function M.save(dir,version)
  local path=M.path(dir)
  local f,e=io.open(path..'.tmp','w'); if not f then return nil,e end
  local wrote,we=f:write('mode_notice_seen=true\nmode_notice_version='..tostring(version)..'\n')
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
