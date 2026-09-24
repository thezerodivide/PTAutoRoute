local M={}
local function safe(s) return tostring(s or 'unknown'):gsub('[^%w_%-]','_') end
function M.new(dir,identity,clock)
  local self={verbose=false}
  function self:path()
    local server,char=identity()
    return dir..'/PTAR_'..safe(server)..'_'..safe(char)..'.log'
  end
  function self:write(level,message)
    if level=='DEBUG' and not self.verbose then return end
    local path=self:path()
    local previous=io.open(path,'rb')
    if previous then
      local size=previous:seek('end'); previous:close()
      if size and size>4*1024*1024 then os.remove(path..'.old'); os.rename(path,path..'.old') end
    end
    local f=io.open(path,'a')
    if not f then return end
    local now=clock()
    f:write(string.format('%s.%03d +%dms | %-5s | %s\n',os.date('%Y-%m-%d %H:%M:%S'),now%1000,now,level,tostring(message)))
    f:close()
  end
  function self:event(message) self:write('EVENT',message) end
  function self:debug(message) self:write('DEBUG',message) end
  function self:set_verbose(enabled,snapshot)
    self.verbose=enabled and true or false
    self:event('Verbose Debug '..(self.verbose and 'ON' or 'OFF'))
    if self.verbose and snapshot then self:debug('Enable snapshot: '..snapshot()) end
  end
  return self
end
return M
