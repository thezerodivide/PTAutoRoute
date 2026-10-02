-- Waypoint-barrier bookkeeping (DL-010). No MacroQuest dependency: PTAR.lua wires it to mq.event and mq.TLO.Group.
-- Two independent kinds of state: heartbeat liveness (who is currently active, for roster membership) and
-- REACHED bookkeeping (who has reached a given waypoint). Barrier state is a set of names per waypoint, never a
-- counter, because the underlying chat event fires three times per line (DL-008).
local M = {}

function M.new()
  local self = { last_heard = {}, seen = {}, medbreak = {} }

  -- Records/refreshes the last time `name` was heard from (a PTAR:HERE heartbeat).
  function self:heartbeat(name, at)
    self.last_heard[name] = at
  end

  -- Filters `candidate_names` down to those with a heartbeat strictly within `expiry_ms` of `now`.
  function self:active_names(candidate_names, now, expiry_ms)
    local out = {}
    for _, name in ipairs(candidate_names) do
      local heard = self.last_heard[name]
      if heard and now - heard < expiry_ms then out[#out + 1] = name end
    end
    return out
  end

  -- Records that `name` has reached `waypoint_id`. Idempotent: repeated calls for the same name are a no-op.
  function self:record_reached(waypoint_id, name)
    local set = self.seen[waypoint_id]
    if not set then set = {}; self.seen[waypoint_id] = set end
    set[name] = true
  end

  -- The set (name -> true) of who has reached `waypoint_id`. Never nil, even if nobody has.
  function self:seen_names(waypoint_id)
    return self.seen[waypoint_id] or {}
  end

  -- Clears REACHED state (called on Start, DL-010), so a fresh run cannot pass every waypoint instantly on stale
  -- state. Heartbeat liveness is untouched -- a teammate that is still actually running PTAR stays known active.
  function self:clear()
    self.seen = {}
    self.medbreak = {}
  end

  -- Med-break tracking (DL-016): a toggle-able set, unlike REACHED's monotonic one -- a break can start and stop
  -- more than once in a single run. `name` is in the set from a PTAR:MEDBREAK:START bark until a matching END.
  function self:mark_medbreak(name)
    self.medbreak[name] = true
  end

  function self:clear_medbreak(name)
    self.medbreak[name] = nil
  end

  -- Filters `candidate_names` (the adapter's already heartbeat-filtered roster) down to those currently marked as
  -- on a med break. Liveness is not re-checked here -- a name that drops out of the live roster is no longer a
  -- candidate at all, so it is excluded without this module needing to know why.
  function self:medbreak_active_names(candidate_names)
    local out = {}
    for _, name in ipairs(candidate_names) do
      if self.medbreak[name] then out[#out + 1] = name end
    end
    return out
  end

  return self
end

return M
