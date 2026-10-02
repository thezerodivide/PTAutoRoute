-- Requirement tests for PTARFiles.scan and PTARFiles.has_endpoint (DL-021 build 2). No MacroQuest dependency: real
-- temp directories and real route files written with PTARRouteData's own serializer.
-- Requirements (developer, 2026-10-02): the Runner's zone filtering needs the readable zone and name of INVALID
-- routes, and a separate `incomplete` flag for a route with no Finish or Manual-handoff waypoint; the Editor's
-- list (its entries, order and labels) must not change.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Files = require 'PTAR.PTARFiles'
local RD = require 'PTAR.PTARRouteData'

local function normal(id) return { id = id, label = 'L ' .. id, type = 'normal', x = 1, y = 2, z = 3, heading = 90 } end
local function finish(id) local w = normal(id); w.type, w.radius = 'finish', 3; return w end
local function route(name, zone, waypoints)
  return { format_version = 3, next_id = 10, route_name = name, zone_short_name = zone, description = '', waypoints = waypoints }
end

local function write_file(dir, name, text)
  local f = assert(io.open(dir .. '/' .. name, 'wb')); f:write(text); f:close()
end
local function write_route(dir, name, rt)
  local text = assert(RD.serialize(rt))
  write_file(dir, name, text)
  return text
end
local function write_index(dir, names)
  write_file(dir, 'PTAR_Routes.txt', table.concat(names, '\n') .. '\n')
end
local function by_file(list)
  local m = {}
  for _, e in ipairs(list) do m[e.file] = e end
  return m
end

test('DL-021: a complete valid route is listed with its zone, name, an unchanged label and incomplete = false', function()
  local dir = T.with_temp_dir()
  write_route(dir, 'PTAR_A.lua', route('Alpha', 'sleeper', { normal('wp_001'), finish('wp_002') }))
  write_index(dir, { 'PTAR_A.lua' })
  local list = Files.scan(dir)
  expect.equal(#list, 1)
  local e = list[1]
  expect.equal(e.zone, 'sleeper'); expect.equal(e.name, 'Alpha'); expect.equal(e.incomplete, false)
  expect.equal(e.error, nil)
  expect.equal(e.label, 'Alpha [sleeper] — PTAR_A.lua')
end)

test('DL-021: a route with no Finish or Manual-handoff waypoint is still listed as valid (Editor unchanged) but flagged incomplete', function()
  local dir = T.with_temp_dir()
  write_route(dir, 'PTAR_B.lua', route('Beta', 'sleeper', { normal('wp_001') }))
  write_index(dir, { 'PTAR_B.lua' })
  local e = Files.scan(dir)[1]
  expect.equal(e.error, nil)
  expect.equal(e.label, 'Beta [sleeper] — PTAR_B.lua')
  expect.equal(e.incomplete, true)
end)

test('DL-021: a route that parses but fails validation exposes its readable zone and name, keeps its error and label', function()
  local dir = T.with_temp_dir()
  local text = assert(RD.serialize(route('Gamma', 'eastwastes', { normal('wp_001'), finish('wp_002') })))
  write_file(dir, 'PTAR_C.lua', (text:gsub('format_version = 3', 'format_version = 99')))
  write_index(dir, { 'PTAR_C.lua' })
  local e = Files.scan(dir)[1]
  expect.truthy(e.error ~= nil)
  expect.equal(e.zone, 'eastwastes'); expect.equal(e.name, 'Gamma')
  expect.equal(e.label, 'PTAR_C.lua [invalid: ' .. e.error .. ']')
end)

test('DL-021: an unreadable route file has an error and no zone or name (so the Runner cannot place it)', function()
  local dir = T.with_temp_dir()
  write_file(dir, 'PTAR_D.lua', 'this is not a route @@@')
  write_index(dir, { 'PTAR_D.lua' })
  local e = Files.scan(dir)[1]
  expect.truthy(e.error ~= nil)
  expect.equal(e.zone, nil); expect.equal(e.name, nil)
end)

test('DL-021: the scan order the Editor sees is unchanged - by file name, case-insensitive, whatever the route names are', function()
  local dir = T.with_temp_dir()
  write_route(dir, 'PTAR_b.lua', route('Aardvark', 'z1', { normal('wp_001'), finish('wp_002') }))
  write_route(dir, 'PTAR_A.lua', route('Zebra', 'z1', { normal('wp_001'), finish('wp_002') }))
  write_index(dir, { 'PTAR_b.lua', 'PTAR_A.lua' })
  local list = Files.scan(dir)
  expect.equal(list[1].file, 'PTAR_A.lua'); expect.equal(list[2].file, 'PTAR_b.lua')
end)

test('DL-021: has_endpoint - a Finish waypoint, a Manual-handoff waypoint and finish_open / finish_zone doors all count', function()
  expect.equal(Files.has_endpoint(route('r', 'z', { normal('wp_001'), finish('wp_002') })), true)
  local handoff = normal('wp_002'); handoff.manual_handoff = true
  expect.equal(Files.has_endpoint(route('r', 'z', { normal('wp_001'), handoff })), true)
  local open = normal('wp_002'); open.type, open.door_after = 'door', 'finish_open'
  expect.equal(Files.has_endpoint(route('r', 'z', { normal('wp_001'), open })), true)
  local zone = normal('wp_002'); zone.type, zone.door_after = 'door', 'finish_zone'
  expect.equal(Files.has_endpoint(route('r', 'z', { normal('wp_001'), zone })), true)
end)

test('DL-021: has_endpoint - an empty route, or one of only normal waypoints, has none', function()
  expect.equal(Files.has_endpoint(route('r', 'z', {})), false)
  expect.equal(Files.has_endpoint(route('r', 'z', { normal('wp_001'), normal('wp_002') })), false)
end)
