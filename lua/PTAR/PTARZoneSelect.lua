-- Zone-filtered route selection for the Runner (DL-021). No MacroQuest dependency: PTAR.lua owns the UI and the
-- zone reading; this module only decides what to list, what the default is, and what a zone change should do.
local M={}

M.INCOMPLETE_REASON='Route is still being captured; add a Finish or Manual handoff waypoint before running.'

local ACTIVE={['Running']=true,['Recovering']=true,['Waiting for combat']=true,['Waiting for med break']=true}
local PRESERVED={['Completed']=true,['Error']=true,['Manual handoff']=true,['Paused']=true}

local function shown_name(entry) return entry.name or entry.file end

-- A route is runnable only if it validates AND has a Finish or Manual-handoff waypoint; anything else shows as
-- invalid in the Runner (the Editor's own list is untouched).
function M.is_valid(entry) return entry.error==nil and not entry.incomplete end
function M.reason(entry)
  if entry.error~=nil then return entry.error end
  if entry.incomplete then return M.INCOMPLETE_REASON end
  return nil
end

-- The routes the Runner's dropdown offers for `zone`. Full view also offers invalid routes whose zone is readable and
-- matches; compact view offers valid routes only. Sorted by shown name (case-insensitive), file name as tie-breaker.
function M.list(entries,zone,view)
  local out={}
  for _,entry in ipairs(entries) do
    if entry.zone~=nil and entry.zone==zone then
      local ok=M.is_valid(entry)
      if ok then
        out[#out+1]={file=entry.file,label=entry.label,valid=true,name=shown_name(entry)}
      elseif view=='full' then
        out[#out+1]={file=entry.file,valid=false,reason=M.reason(entry),name=shown_name(entry),
          label='[INVALID] '..shown_name(entry)..' ['..zone..'] — '..entry.file}
      end
    end
  end
  table.sort(out,function(a,b)
    local an,bn=a.name:lower(),b.name:lower()
    if an~=bn then return an<bn end
    return a.file<b.file
  end)
  return out
end

-- The file to load for `zone`: its remembered route if that is still a valid route for the zone, otherwise the first
-- valid route alphabetically, otherwise nil. Never an invalid or incomplete route.
function M.default_file(entries,zone,remembered)
  local valid=M.list(entries,zone,'compact')
  if remembered then
    for _,entry in ipairs(valid) do if entry.file==remembered then return remembered end end
  end
  return valid[1] and valid[1].file or nil
end

-- What a zone reading means. Only a non-empty zone that differs from the last known one is a change.
function M.zone_event(zone,last_zone)
  if zone==nil or zone=='' then return 'unavailable' end
  if zone==last_zone then return 'same' end
  return 'changed'
end

-- What to do about the runner when the zone changed (or an update that was deferred can now be applied).
-- 'defer' while a run is active; 'load_default' with no runner or a Ready one; for the preserved states
-- (Completed, Error, Manual handoff, Paused) 'restore' the loaded route when the zone is its own stored zone,
-- otherwise 'pending'.
function M.decide(zone,status,loaded_zone)
  if status==nil or status=='Ready' then return 'load_default' end
  if ACTIVE[status] then return 'defer' end
  if PRESERVED[status] and loaded_zone~=nil and loaded_zone==zone then return 'restore' end
  return 'pending'
end

-- The log line for one zone-update decision (logging standard, Protocol 8): what was decided and the state that drove it.
function M.update_line(action,zone,status,loaded,displayed)
  return 'Zone update: '..action..'; zone '..tostring(zone)..'; runner '..(status or 'none')..'; loaded '..(loaded or 'none')
    ..'; displayed '..(displayed or 'none')
end

return M
