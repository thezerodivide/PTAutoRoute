-- Requirement tests for PTARRouteData. Every test names the spec line it comes from
-- (docs/PTAR_Rebaseline_Spec.md, line numbers as of 2026-09-28). Expected values come from the spec, not from code output.
local T = require 'harness.t'
local fs = require 'harness.fs'
local test, expect = T.test, T.expect
local BS = string.char(92)

local RD = T.fresh_require('PTAR.PTARRouteData')

local function normal(id) return { id = id, label = 'L ' .. id, type = 'normal', x = 1, y = 2, z = 3, heading = 90 } end

local function ground_traverse(id)
  local w = normal(id)
  w.type, w.radius, w.phases = 'traverse', 3, { 'fall' }
  w.ledge = { x = 1, y = 2, z = 3 }
  w.exit = { x = 4, y = 5, z = 6, radius = 5 }
  return w
end

local function water_drop(id)
  local w = ground_traverse(id)
  w.phases = { 'fall', 'descend', 'cross', 'ascend' }
  w.underwater_target = { x = 7, y = 8, z = 9, radius = 4 }
  return w
end

local function water_cross(id)
  local w = water_drop(id)
  w.phases, w.ledge = { 'descend', 'cross', 'ascend' }, nil
  return w
end

local function finish(id)
  local w = normal(id)
  w.type, w.radius = 'finish', 3
  return w
end

local function route(waypoints, next_id)
  return { format_version = 3, next_id = next_id or 10, route_name = 'R', zone_short_name = 'zone',
           description = '', waypoints = waypoints or { normal('wp_001'), finish('wp_002') } }
end

local function joined(errors) return table.concat(errors, ' | ') end

local function write_file(path, text)
  local f = assert(io.open(path, 'wb'))
  f:write(text)
  f:close()
end

local function valid_text(r) return assert(RD.serialize(r or route())) end

-- ---------------------------------------------------------------- spec l45
test('spec l45: route format_version is 3', function()
  expect.equal(RD.FORMAT_VERSION, 3)
end)

test('spec l45: the four waypoint types normal/door/traverse/finish validate; others do not', function()
  local errs = RD.validate(route({ normal('wp_001'), finish('wp_002') }))
  expect.equal(#errs, 0)
  local bad = normal('wp_001')
  bad.type = 'teleport'
  T.assert_contains(joined((RD.validate(route({ bad })))), 'invalid type')
end)

-- ---------------------------------------------------------------- spec l31
test('spec l31: an unsupported format_version is hard-rejected (older and newer)', function()
  for _, v in ipairs({ 2, 4 }) do
    local r = route()
    r.format_version = v
    T.assert_contains(joined((RD.validate(r))), 'Unsupported')
    local text, err = RD.serialize(r)
    expect.equal(text, nil)
    T.assert_contains(err, 'Unsupported')
  end
end)

-- ---------------------------------------------------------------- spec l26
local rejected_sources = {
  ['a function call'] = 'return os.execute("echo hi")',
  ['a bare statement'] = 'x = 1',
  ['trailing code after the table'] = 'return {} print(1)',
  ['a call inside a field'] = 'return { a = f() }',
  ['arithmetic'] = 'return { a = 1 + 2 }',
  ['parenthesised expression'] = 'return { a = (1) }',
  ['setmetatable'] = 'return setmetatable({}, {})',
  ['a bare identifier as a value'] = 'return { a = os }',
}
for label, src in pairs(rejected_sources) do
  test('spec l26: a route file containing ' .. label .. ' is rejected as non-data', function()
    local path = T.with_temp_dir() .. BS .. 'r.lua'
    write_file(path, src)
    local r, err = RD.read(path)
    expect.equal(r, nil)
    T.assert_contains(err, 'non-data route')
  end)
end

test('spec l26: literal data (comments, negative numbers, booleans, text that merely looks like code) is accepted', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  write_file(path, '-- comment\nreturn {\n  --[[ block ]] a = -1.5, b = true, [1] = "os.execute(1)", c = { d = false },\n}\n')
  local r = assert(RD.read(path))
  expect.equal(r, { a = -1.5, b = true, [1] = 'os.execute(1)', c = { d = false } })
end)

-- ---------------------------------------------------------------- spec l46-l49
test('spec l46: the three traversal presets validate', function()
  for _, w in ipairs({ ground_traverse('wp_001'), water_drop('wp_001'), water_cross('wp_001') }) do
    local errs = RD.validate(route({ w, finish('wp_002') }))
    expect.equal(errs, {})
  end
end)

test('spec l46: any other phase list is rejected', function()
  for _, phases in ipairs({ { 'cross' }, { 'fall', 'cross' }, { 'descend', 'cross' }, { 'ascend', 'cross', 'descend' }, {} }) do
    local w = ground_traverse('wp_001')
    w.phases = phases
    T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'unsupported traversal phases')
  end
end)

test('spec l47: traversal departure/approach radius is capped at 5 (5 accepted, above 5 rejected)', function()
  local w = ground_traverse('wp_001')
  w.radius = 5
  expect.equal(RD.validate(route({ w, finish('wp_002') })), {})
  w.radius = 5.01
  T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'radius from 0 to 5')
end)

test('spec l48: water presets require an underwater target with a positive radius; ground must not have one', function()
  local w = water_drop('wp_001')
  w.underwater_target.radius = nil
  T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'underwater target')
  w = water_cross('wp_001')
  w.underwater_target = nil
  T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'underwater target')
  w = ground_traverse('wp_001')
  w.underwater_target = { x = 1, y = 2, z = 3, radius = 4 }
  T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'ground traverse cannot have an underwater target')
end)

test('spec l49: exit radius is required on every traverse preset, including ground', function()
  for _, make in ipairs({ ground_traverse, water_drop, water_cross }) do
    local w = make('wp_001')
    w.exit.radius = nil
    T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'exit X/Y/Z and positive radius')
  end
end)

test('spec l50: a ledge exists only when there is a fall phase (water_cross with a ledge is rejected)', function()
  local w = water_cross('wp_001')
  w.ledge = { x = 1, y = 2, z = 3 }
  T.assert_contains(joined((RD.validate(route({ w, finish('wp_002') })))), 'cannot have a ledge')
end)

-- ---------------------------------------------------------------- spec l55
test('spec l55: door outcomes are exactly continue / finish_open / finish_zone', function()
  local function door(after)
    local w = normal('wp_001')
    w.type, w.door, w.door_after = 'door', { id = 5, name = 'd', x = 1, y = 2, z = 3 }, after
    return route({ w, finish('wp_002') })
  end
  for _, ok in ipairs({ 'continue', 'finish_open', 'finish_zone' }) do
    expect.equal(#RD.validate(door(ok)), 0)
  end
  T.assert_contains(joined((RD.validate(door('open_sesame')))), 'door_after requires')
end)

-- ---------------------------------------------------------------- spec l30 (atomic save) and l64 (recovery)
test('spec l30: save round-trips the route exactly', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  local r = route({ normal('wp_001'), water_drop('wp_002'), finish('wp_003') })
  assert(RD.save(r, path))
  expect.equal(assert(RD.read(path)), r)
end)

test('spec l30: a second save retains the previous main as .bak and leaves no .tmp', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  local first = route()
  assert(RD.save(first, path))
  local first_text = fs.read_all(path)
  local second = route()
  second.route_name = 'Renamed'
  assert(RD.save(second, path))
  expect.equal(fs.read_all(path .. '.bak'), first_text)
  expect.equal(assert(RD.read(path)).route_name, 'Renamed')
  expect.falsy(fs.exists(path .. '.tmp'))
end)

test('spec l30: saving an invalid route is refused and the existing main is untouched', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  assert(RD.save(route(), path))
  local before = fs.read_all(path)
  local bad = route()
  bad.route_name = ''
  local ok, err = RD.save(bad, path)
  expect.equal(ok, nil)
  T.assert_contains(err, 'Route name is required')
  expect.equal(fs.read_all(path), before)
end)

test('spec l64: recovery prefers a valid main over leftover .tmp and .bak', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  local main, other = route(), route()
  main.route_name, other.route_name = 'main', 'other'
  write_file(path, valid_text(main))
  write_file(path .. '.tmp', valid_text(other))
  write_file(path .. '.bak', valid_text(other))
  local got, note = RD.recover(path)
  expect.equal(got.route_name, 'main')
  expect.equal(note, nil)
end)

test('spec l64: with no valid main, a valid .tmp is used (and promoted) before .bak', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  local tmp, bak = route(), route()
  tmp.route_name, bak.route_name = 'tmp', 'bak'
  write_file(path, 'garbage')
  write_file(path .. '.tmp', valid_text(tmp))
  write_file(path .. '.bak', valid_text(bak))
  local got, note = RD.recover(path)
  expect.equal(got.route_name, 'tmp')
  T.assert_contains(note, 'Recovered validated temporary route')
  expect.equal(assert(RD.read(path)).route_name, 'tmp')
end)

test('spec l64: with neither main nor .tmp valid, the .bak is restored', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  local bak = route()
  bak.route_name = 'bak'
  write_file(path .. '.tmp', 'garbage')
  write_file(path .. '.bak', valid_text(bak))
  local got, note = RD.recover(path)
  expect.equal(got.route_name, 'bak')
  T.assert_contains(note, 'Recovered validated backup')
  expect.equal(assert(RD.read(path)).route_name, 'bak')
end)

test('spec l64: with nothing valid, recovery reports failure for all three files', function()
  local path = T.with_temp_dir() .. BS .. 'r.lua'
  write_file(path, 'garbage')
  local got, note = RD.recover(path)
  expect.equal(got, nil)
  T.assert_contains(note, 'No valid route')
  T.assert_contains(note, 'main=')
  T.assert_contains(note, 'tmp=')
  T.assert_contains(note, 'bak=')
end)
