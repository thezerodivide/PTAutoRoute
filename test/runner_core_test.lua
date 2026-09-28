-- Requirement tests for PTARRunnerCore. Each test names the decision-log entry (docs/decision_log.md) or spec
-- line its expectation comes from. The runner is driven only through its public API (start/resume/pause/stop/
-- tick) with a scripted fake io (test/harness/sim.lua); assertions are on status, phase, message and the calls
-- the runner made to the game.
local T = require 'harness.t'
local Sim = require 'harness.sim'
local test, expect = T.test, T.expect

local Core = require 'PTAR.PTARRunnerCore'

local TRAVERSAL_PHASES = { 'traverse_facing', 'traverse_approach', 'traverse_falling',
                           'water_facing', 'water_descend', 'water_cross', 'water_ascend' }

local function wp(id, x, y, z, extra)
  local w = { id = id, label = id, type = 'normal', x = x, y = y, z = z, heading = 90 }
  for k, v in pairs(extra or {}) do w[k] = v end
  return w
end

local function route(waypoints)
  return { format_version = 3, next_id = 100, route_name = 'R', zone_short_name = 'zone', description = '', waypoints = waypoints }
end

-- Water-drop traverse at the origin followed by a finish at its exit.
local function water_route()
  return route({
    wp('wp_001', 0, 0, 0, { type = 'traverse', radius = 3, phases = { 'fall', 'descend', 'cross', 'ascend' },
      ledge = { x = 0, y = -50, z = 0 }, underwater_target = { x = 0, y = -80, z = -60, radius = 4 },
      exit = { x = 0, y = -120, z = -40, radius = 5 } }),
    wp('wp_002', 0, -120, -40, { type = 'finish', radius = 5 }),
  })
end

-- Ground-drop traverse at the origin. By default the exit is far from the landing point, so a ground_exit leg is needed.
local function ground_route(exit, extra)
  local rt = route({
    wp('wp_001', 0, 0, 0, { type = 'traverse', radius = 3, phases = { 'fall' },
      ledge = { x = 0, y = -50, z = 0 }, exit = exit or { x = 0, y = -60, z = -40, radius = 5 } }),
    wp('wp_002', 0, -60, -40, { type = 'finish', radius = 5 }),
  })
  for k, v in pairs(extra or {}) do rt.waypoints[1][k] = v end
  return rt
end

local function far_route()
  return route({ wp('wp_001', 0, -200, 0, { radius = 5 }), wp('wp_002', 0, -400, 0, { type = 'finish', radius = 5 }) })
end

-- Drives the runner through legitimate ticks until it is in `target` ('landed' = just after the fall settles,
-- whatever phase that leads to). Returns runner, sim, and the current time.
local function to_phase(rt, target)
  local s = Sim.new()
  local r = Core.new(rt, s.io)
  local t = 1000
  local function tick(dt) t = t + (dt or 100); r:tick(t) end
  r:start(1, t)
  tick()                                          -- within radius of the traverse: begin_traverse
  if r.phase == target then return r, s, t end
  s.heading = 90; tick()                          -- heading verified: approach begins
  if r.phase == target then return r, s, t end
  s.p.z = -2; tick()                              -- 20 Z/s: fall starts
  if r.phase == target then return r, s, t end
  s.feet = true
  s.p.z = -30; tick()                             -- still dropping
  tick(); tick(400); tick(400)                    -- vertical speed ~0 for >= 750 ms: landing
  if r.phase == target or target == 'landed' then return r, s, t end
  s.heading = s.bearing; tick()                   -- water_facing -> water_descend
  if r.phase == target then return r, s, t end
  s.head, s.p.z = true, -60; tick()               -- deep enough: water_cross
  if r.phase == target then return r, s, t end
  s.p.y = -80; tick()                             -- at the underwater target: water_ascend
  if r.phase == target then return r, s, t end
  error('to_phase: could not reach ' .. target .. ' (stopped in ' .. tostring(r.phase) .. ')')
end

-- ================================================================ DL-001
for _, phase in ipairs(TRAVERSAL_PHASES) do
  test('DL-001: Start, Resume and Use-Nearest are blocked in phase ' .. phase .. ' and issue no game commands', function()
    local r, s, t = to_phase(water_route(), phase)
    expect.equal(r.phase, phase)
    local before = #s.calls
    local status_before = r.status
    r:start(1, t + 10)
    T.assert_contains(r.message, 'Start/Resume blocked')
    T.assert_contains(r.message, phase)
    r:resume(t + 20)
    T.assert_contains(r.message, 'Start/Resume blocked')
    r:start_nearest(t + 30)
    T.assert_contains(r.message, 'Start/Resume blocked')
    expect.equal(#s.calls, before)   -- no /nav, no stop, no key release: nothing was touched
    expect.equal(r.phase, phase)
    expect.equal(r.status, status_before)
  end)
end

test('DL-001: Use-Nearest during a traversal names the traversal block even when no other waypoint is reachable', function()
  local r, s, t = to_phase(water_route(), 'traverse_approach')
  s.path = false
  r:start_nearest(t + 10)
  T.assert_contains(r.message, 'Start/Resume blocked')
  expect.falsy(r.message:find('No reachable dry waypoint', 1, true))
end)

test('DL-001: Start is not over-blocked during ordinary navigation (pause, then start again works)', function()
  local s = Sim.new()
  local r = Core.new(far_route(), s.io)
  r:start(1, 1000)
  expect.equal(s.count('nav'), 1)
  r:pause()
  expect.equal(r.status, 'Paused')
  r:start(1, 2000)
  expect.equal(r.status, 'Running')
  expect.equal(s.count('nav'), 2)
  expect.falsy(r.message:find('blocked', 1, true))
end)

test('DL-001: Stop clears the guard, so Start works again after stopping mid-traversal', function()
  local r, s, t = to_phase(water_route(), 'traverse_approach')
  r:stop()
  expect.equal(r.status, 'Ready')
  s.p = { x = 0, y = 0, z = 0 }
  r:start(1, t + 100)
  expect.equal(r.status, 'Running')
  expect.falsy(r.message:find('blocked', 1, true))
end)

test('DL-001: a traverse that ends the route by manual handoff straight from landing does not leave Start blocked', function()
  -- Exit already within radius: landing goes directly to advance(), which must leave no stale traversal phase.
  local r, s, t = to_phase(ground_route({ x = 0, y = 0, z = -30, radius = 5 }, { manual_handoff = true }), 'landed')
  expect.equal(r.status, 'Manual handoff')
  local navs = s.count('nav')
  r:start(1, t + 100)
  expect.falsy(r.message:find('blocked', 1, true))
  expect.equal(r.status, 'Running')
  expect.equal(s.count('nav'), navs + 1)
end)

-- ================================================================ DL-006
for _, phase in ipairs(TRAVERSAL_PHASES) do
  test('DL-006: combat has no effect on the runner in phase ' .. phase, function()
    local function next_tick(combat)
      local r, s, t = to_phase(water_route(), phase)
      s.combat = combat
      r:tick(t + 100)
      return { status = r.status, phase = r.phase, message = r.message, calls = s.names() }
    end
    local with_combat, without = next_tick(true), next_tick(false)
    expect.equal(with_combat, without)   -- "runs exactly as if not in combat"
    expect.truthy(with_combat.phase ~= 'combat')
    expect.truthy(with_combat.status ~= 'Waiting for combat')
  end)
end

test('DL-006: combat during ground_exit pauses the leg (Waiting for combat) instead of failing', function()
  local r, s, t = to_phase(ground_route(), 'ground_exit')
  local stops = s.count('nav_stop')
  s.combat = true
  r:tick(t + 100)
  expect.equal(r.status, 'Waiting for combat')
  expect.equal(r.phase, 'combat')
  expect.truthy(s.count('nav_stop') > stops)
end)

test('DL-006: after combat clears, ground_exit resumes by re-issuing /nav to the captured EXIT, not the waypoint', function()
  local rt = ground_route()
  local r, s, t = to_phase(rt, 'ground_exit')
  s.combat = true
  r:tick(t + 100)
  s.combat = false
  local navs = s.count('nav')
  r:tick(t + 200)                       -- clear window starts
  expect.equal(r.phase, 'combat')
  expect.equal(s.count('nav'), navs)    -- not resumed immediately
  r:tick(t + 3000)                      -- well past the clear delay
  expect.equal(r.phase, 'ground_exit')
  expect.equal(s.count('nav'), navs + 1)
  expect.truthy(s.last('nav')[1] == rt.waypoints[1].exit)
end)

test('DL-006: ordinary nav combat still pauses and resumes toward the same waypoint (spec s4 unchanged)', function()
  local rt = far_route()
  local s = Sim.new()
  local r = Core.new(rt, s.io)
  r:start(1, 1000)
  s.combat = true
  r:tick(1100)
  expect.equal(r.status, 'Waiting for combat')
  s.combat = false
  local navs = s.count('nav')
  r:tick(1200)
  r:tick(4000)
  expect.equal(s.count('nav'), navs + 1)
  expect.truthy(s.last('nav')[1] == rt.waypoints[1])
end)

-- ================================================================ DL-007
-- Geometry is the real incident (DL-007): wp_060 departure and ledge, 3D distance ~103.2, so limit ~148.2.
local function approach_route()
  return route({
    wp('wp_060', 619.659, -2236.979, -444.873, { type = 'traverse', radius = 3, phases = { 'fall' },
      ledge = { x = 617.781, y = -2335.123, z = -412.873 }, exit = { x = 619, y = -2400, z = -450, radius = 5 } }),
    wp('wp_061', 619, -2400, -450, { type = 'finish', radius = 5 }),
  })
end

local function approach_after_walking(distance)
  local rt = approach_route()
  local s = Sim.new()
  s.p = { x = 619.659, y = -2236.979, z = -444.873 }
  local r = Core.new(rt, s.io)
  r:start(1, 1000)
  r:tick(1100)                    -- traverse_facing
  s.heading = 90
  r:tick(1200)                    -- traverse_approach; origin recorded here
  expect.equal(r.phase, 'traverse_approach')
  s.p.y = s.p.y - distance        -- walk straight ahead, level with the origin
  r:tick(1300)
  return r
end

for _, d in ipairs({ 113.6, 146 }) do
  test('DL-007: an approach of ' .. d .. ' units toward a ledge ~103.2 units away (3D) does not fail', function()
    local r = approach_after_walking(d)
    expect.equal(r.status, 'Running')
    expect.equal(r.phase, 'traverse_approach')
  end)
end

test('DL-007: an approach beyond ledge distance (3D) + 45 fails, naming the 148.2 limit', function()
  local r = approach_after_walking(150)
  expect.equal(r.status, 'Error')
  T.assert_contains(r.message, 'Fall approach passed 148.2-unit limit')
end)

-- ================================================================ DL-008
local function door_route(after)
  return route({
    wp('wp_001', 0, 0, 0, { type = 'door', door_after = after, door = { id = 77, name = 'door', x = 0, y = 0, z = 0 } }),
    wp('wp_002', 0, -100, 0, { type = 'finish', radius = 5 }),
  })
end

-- Runner standing at the door waypoint, in the door phase, with the given role.
local function at_door(role, after)
  local s = Sim.new()
  s.role = role
  local r = Core.new(door_route(after), s.io)
  r:start(1, 1000)
  r:tick(1100)
  expect.equal(r.phase, 'door')
  return r, s, 1100
end

local function advanced_to_next_waypoint(r, s)
  return r.index == 2 and s.last('nav') ~= nil and s.last('nav')[1].id == 'wp_002'
end

test('DL-008: a primary that sees the door open advances and announces it exactly once', function()
  local r, s, t = at_door('primary')
  s.door_state = true
  r:tick(t + 400)
  expect.truthy(advanced_to_next_waypoint(r, s))
  expect.equal(s.count('announce'), 1)
  expect.equal(s.last('announce')[1], 77)
end)

test('DL-008: a secondary that itself sees the door open advances without announcing', function()
  local r, s, t = at_door('secondary')
  s.door_state = true
  r:tick(t + 400)
  expect.truthy(advanced_to_next_waypoint(r, s))
  expect.equal(s.count('announce'), 0)
end)

test('DL-008: a secondary advances on a group-chat confirmation without ever clicking', function()
  local r, s, t = at_door('secondary')
  s.door_state = false
  s.confirmed[77] = true
  r:tick(t + 400)
  expect.truthy(advanced_to_next_waypoint(r, s))
  expect.equal(s.count('door'), 0)
end)

test('DL-008: a secondary never clicks, even after its own wait times out; the leg ends in Error', function()
  local r, s, t = at_door('secondary')
  s.door_state = false
  local now = t
  while now < t + 120000 and r.status ~= 'Error' do
    now = now + 300
    r:tick(now)
  end
  expect.equal(r.status, 'Error')       -- bounded: it gives up rather than waiting forever
  expect.equal(s.count('door'), 0)      -- and never clicked
end)

test('DL-008: a primary whose door state is unavailable proceeds but does NOT announce', function()
  local r, s, t = at_door('primary')
  s.door_state, s.door_detail = nil, 'unavailable'
  local now = t
  while now < t + 10000 and r.index ~= 2 do
    now = now + 300
    r:tick(now)
  end
  expect.truthy(advanced_to_next_waypoint(r, s))
  expect.equal(s.count('announce'), 0)
end)

test('DL-008: a primary facing a closed door clicks it, then advances and announces once it reads open', function()
  local r, s, t = at_door('primary')
  s.door_state = false
  r:tick(t + 400)
  expect.equal(s.count('door'), 1)
  expect.equal(s.last('door')[2], nil)  -- an ordinary click, not the forced zoning click
  expect.equal(r.index, 1)
  s.door_state = true
  r:tick(t + 800)
  expect.truthy(advanced_to_next_waypoint(r, s))
  expect.equal(s.count('announce'), 1)
end)

test('DL-008: finish_zone is untouched - a secondary still clicks its own zoning door', function()
  local r, s, t = at_door('secondary', 'finish_zone')
  s.door_state = false
  r:tick(t + 400)
  expect.equal(s.count('door'), 1)
  expect.equal(s.last('door')[2], true)
  expect.equal(r.phase, 'door_zone')
end)

test('DL-008: finish_open shares the continue branch - a primary announces and the route completes', function()
  local r, s, t = at_door('primary', 'finish_open')
  s.door_state = true
  r:tick(t + 400)
  expect.equal(s.count('announce'), 1)
  expect.equal(r.status, 'Completed')
end)
