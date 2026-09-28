-- Scripted fake of the RunnerCore `io` adapter (the seam PTARRunnerCore already defines). Tests set the
-- sim's state (position, heading, wetness, combat, door state, role, ...) and read back what the runner
-- asked the game to do. It implements exactly the io functions PTARRunnerCore calls; calling anything
-- else is an error, so a new dependency in the state machine surfaces here instead of passing silently.
local M = {}

function M.new()
  local s = {
    p = { x = 0, y = 0, z = 0 }, heading = 0, bearing = 180, zone = 'zone',
    mesh = true, path = true, combat = false, nav_active = true,
    feet = false, head = false,
    door_state = false, door_detail = nil, door_click_result = 'clicked',
    role = 'primary', confirmed = {},
    calls = {}, logs = {},
  }
  local function rec(name, ...) s.calls[#s.calls + 1] = { name = name, ... } end

  local io = {}
  io.log = function(m) s.logs[#s.logs + 1] = m end
  io.vertical = function(d, on) rec('vertical', d, on) end
  io.forward = function(on) rec('forward', on) end
  io.nav_stop = function() rec('nav_stop') end
  io.position = function() return { x = s.p.x, y = s.p.y, z = s.p.z } end
  io.combat = function() return s.combat end
  io.mesh = function() return s.mesh end
  io.path = function(w)
    if type(s.path) == 'function' then return s.path(w) end
    return s.path
  end
  io.nav = function(w) rec('nav', w) end
  io.zone = function() return s.zone end
  io.face = function(h) rec('face', h) end
  io.bearing = function() return s.bearing end
  io.wet = function() return s.feet, s.head end
  io.heading = function() return s.heading end
  io.door_state = function() return s.door_state, s.door_detail end
  io.door = function(w, force) rec('door', w, force); return s.door_click_result end
  io.door_confirmed = function(id) return s.confirmed[id] == true end
  io.door_role = function() return s.role end
  io.announce_door_open = function(id) rec('announce', id) end
  io.nav_active = function() return s.nav_active end
  s.io = setmetatable(io, { __index = function(_, k) error('sim: RunnerCore called an io function the sim does not implement: ' .. tostring(k), 2) end })

  function s.count(name)
    local n = 0
    for _, c in ipairs(s.calls) do if c.name == name then n = n + 1 end end
    return n
  end
  function s.last(name)
    for i = #s.calls, 1, -1 do if s.calls[i].name == name then return s.calls[i] end end
  end
  function s.names()
    local out = {}
    for i, c in ipairs(s.calls) do out[i] = c.name end
    return out
  end
  return s
end

return M
