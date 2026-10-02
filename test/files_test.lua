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

-- ================================================================ DL-022 (delete a route from the Editor)
-- Requirements (developer, 2026-10-02): the route's entry is removed from the index FIRST (atomic), then the route file and
-- its .bak/.tmp siblings are deleted as one set; if the index update fails nothing is deleted; if the file cannot be deleted
-- after the entry is gone the route leaves the list, the file stays, and the message points to Register Existing File;
-- success is reported only after every step. The delete path is built only from an accepted PTAR route file name. Real
-- failures are produced with real files (an open file cannot be deleted on Windows; a directory in the way blocks the index
-- write), not with test hooks.
local function exists(path) local f = io.open(path, 'rb'); if f then f:close(); return true end; return false end
local function read_all(path) local f = assert(io.open(path, 'rb')); local t = f:read('*a'); f:close(); return t end
local function set_of(dir)
  write_route(dir, 'PTAR_A.lua', route('Alpha', 'sleeper', { normal('wp_001'), finish('wp_002') }))
  write_route(dir, 'PTAR_B.lua', route('Beta', 'sleeper', { normal('wp_001'), finish('wp_002') }))
  write_file(dir .. '', 'PTAR_A.lua.bak', 'bak text')
  write_file(dir .. '', 'PTAR_A.lua.tmp', 'tmp text')
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua' })
end
local function listed(dir) local out = {}; for _, e in ipairs(Files.scan(dir)) do out[#out + 1] = e.file end; return table.concat(out, ',') end
-- The index is written in text mode, so it has CRLF line endings on Windows; compare it line-ending-neutral.
local function names_in_index(dir) return (read_all(dir .. '/PTAR_Routes.txt'):gsub('\r', '')) end

-- ---------------------------------------------------------------- Files.remove (the index entry)
test('DL-022: remove takes only the named entry out of the index and keeps the others in order', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua', 'PTAR_C.lua' })
  expect.equal(Files.remove(dir, 'PTAR_B.lua'), true)
  expect.equal(names_in_index(dir), 'PTAR_A.lua\nPTAR_C.lua\n')
end)

test('DL-022: removing a name that is not listed succeeds and leaves the index as it was', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua' })
  expect.equal(Files.remove(dir, 'PTAR_Z.lua'), true)
  expect.equal(names_in_index(dir), 'PTAR_A.lua\n')
end)

test('DL-022: removing keeps a .bak of the previous index (same atomic pattern as adding)', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua' })
  Files.remove(dir, 'PTAR_A.lua')
  expect.equal(read_all(dir .. '/PTAR_Routes.txt.bak'), 'PTAR_A.lua\nPTAR_B.lua\n')
end)

test('DL-022: when the index cannot be written, remove fails with a reason and the index is unchanged', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua' })
  os.execute('mkdir "' .. (dir .. '/PTAR_Routes.txt.tmp'):gsub('/', '\\') .. '"')   -- a directory where the .tmp file must go
  local ok, err = Files.remove(dir, 'PTAR_A.lua')
  expect.equal(ok, nil); expect.truthy(type(err) == 'string' and #err > 0)
  expect.equal(names_in_index(dir), 'PTAR_A.lua\nPTAR_B.lua\n')
end)

-- ---------------------------------------------------------------- Files.delete_route (the whole set)
test('DL-022: deleting a route removes its index entry, the route file, and the .bak and .tmp siblings, and nothing else', function()
  local dir = T.with_temp_dir(); set_of(dir)
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  expect.equal(r.ok, true); expect.equal(r.index_removed, true); expect.equal(#r.removed, 3)
  expect.equal(exists(dir .. '/PTAR_A.lua'), false); expect.equal(exists(dir .. '/PTAR_A.lua.bak'), false)
  expect.equal(exists(dir .. '/PTAR_A.lua.tmp'), false)
  expect.equal(exists(dir .. '/PTAR_B.lua'), true)                       -- another route is untouched
  expect.equal(listed(dir), 'PTAR_B.lua')
end)

test('DL-022: a route with no siblings is deleted too', function()
  local dir = T.with_temp_dir()
  write_route(dir, 'PTAR_A.lua', route('Alpha', 'z', { normal('wp_001'), finish('wp_002') })); write_index(dir, { 'PTAR_A.lua' })
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  expect.equal(r.ok, true); expect.equal(#r.removed, 1); expect.equal(listed(dir), '')
end)

test('DL-022: a route whose file is already gone is still taken out of the list and reported as deleted', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua' })
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  expect.equal(r.ok, true); expect.equal(r.index_removed, true); expect.equal(#r.removed, 0)
  expect.equal(listed(dir), '')
end)

test('DL-022: a name that is not an accepted PTAR route file name deletes nothing and touches nothing', function()
  local dir = T.with_temp_dir()
  local outside = dir .. '/../PTAR_Outside_' .. tostring(os.time()) .. '.lua'
  write_file(dir, '../' .. outside:match('[^/]+$'), 'outside')
  write_index(dir, { 'PTAR_A.lua' })
  for _, bad in ipairs({ '../' .. outside:match('[^/]+$'), 'PTAR_x.txt', 'notes.lua', '', 'PTAR_a b.lua' }) do
    local r = Files.delete_route(dir, bad)
    expect.equal(r.ok, false, bad); expect.equal(r.stage, 'name', bad)
  end
  expect.equal(exists(outside), true)
  expect.equal(Files.delete_route(dir, nil).stage, 'name')
  expect.equal(names_in_index(dir), 'PTAR_A.lua\n')
  os.remove(outside)
end)

test('DL-022: if the index cannot be updated nothing is deleted (route file and siblings stay)', function()
  local dir = T.with_temp_dir(); set_of(dir)
  os.execute('mkdir "' .. (dir .. '/PTAR_Routes.txt.tmp'):gsub('/', '\\') .. '"')
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  expect.equal(r.ok, false); expect.equal(r.stage, 'index'); expect.equal(r.index_removed, false)
  expect.equal(exists(dir .. '/PTAR_A.lua'), true); expect.equal(exists(dir .. '/PTAR_A.lua.bak'), true)
  expect.equal(exists(dir .. '/PTAR_A.lua.tmp'), true)
end)

test('DL-022: if the route file cannot be deleted the entry is already gone, the file stays, and the failure names the file stage', function()
  local dir = T.with_temp_dir(); set_of(dir)
  local held = assert(io.open(dir .. '/PTAR_A.lua', 'rb'))              -- an open file cannot be deleted on Windows
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  held:close()
  expect.equal(r.ok, false); expect.equal(r.stage, 'file'); expect.equal(r.index_removed, true)
  expect.truthy(type(r.error) == 'string' and #r.error > 0)
  expect.equal(exists(dir .. '/PTAR_A.lua'), true)
  expect.equal(listed(dir), 'PTAR_B.lua')                                -- it has left the list
end)

test('DL-022: if a sibling cannot be deleted the route is gone, the other sibling is still removed, and the sibling stage names it', function()
  local dir = T.with_temp_dir(); set_of(dir)
  local held = assert(io.open(dir .. '/PTAR_A.lua.bak', 'rb'))
  local r = Files.delete_route(dir, 'PTAR_A.lua')
  held:close()
  expect.equal(r.ok, false); expect.equal(r.stage, 'sibling'); expect.equal(r.failed_file, 'PTAR_A.lua.bak')
  expect.equal(exists(dir .. '/PTAR_A.lua'), false); expect.equal(exists(dir .. '/PTAR_A.lua.tmp'), false)
  expect.equal(exists(dir .. '/PTAR_A.lua.bak'), true)
  expect.equal(r.index_removed, true)
end)

-- ---------------------------------------------------------------- the messages (exact wording, developer-approved)
test('DL-022: the success message is exactly the approved text', function()
  local r = { ok = true, name = 'PTAR_A.lua', index_removed = true, removed = { 'PTAR_A.lua' } }
  expect.equal(Files.delete_message(r), 'Delete confirmed: PTAR_A.lua has been deleted. Refresh Routes in the Runner to update its list.')
end)

test('DL-022: each failure and partial failure has its own explanation, and none of them says "Delete confirmed"', function()
  local cases = {
    { { ok = false, stage = 'name', name = 'x.txt' }, 'Delete failed: x.txt is not a PTAR route file name.' },
    { { ok = false, stage = 'index', name = 'PTAR_A.lua', error = 'Permission denied' },
      'Delete failed: PTAR_A.lua was not deleted. The route list could not be updated: Permission denied' },
    { { ok = false, stage = 'file', name = 'PTAR_A.lua', error = 'Permission denied', index_removed = true },
      'Delete incomplete: PTAR_A.lua was removed from the list, but the file could not be deleted: Permission denied. Use Register Existing File to restore it.' },
    { { ok = false, stage = 'sibling', name = 'PTAR_A.lua', failed_file = 'PTAR_A.lua.bak', error = 'Permission denied', index_removed = true },
      'Delete incomplete: PTAR_A.lua was deleted, but PTAR_A.lua.bak could not be removed: Permission denied. Remove it by hand before reusing the name.' },
  }
  for _, c in ipairs(cases) do
    expect.equal(Files.delete_message(c[1]), c[2])
    expect.equal(Files.delete_message(c[1]):find('Delete confirmed', 1, true), nil)
  end
end)

test('DL-022: the Editor log lines follow the approved forms for success and for each failure stage', function()
  local ok = Files.delete_log_lines({ ok = true, name = 'PTAR_A.lua', index_removed = true,
    removed = { 'PTAR_A.lua', 'PTAR_A.lua.bak' } })
  expect.equal(table.concat(ok, '|'), 'Delete route: index entry removed|Delete route: removed PTAR_A.lua|Delete route: removed PTAR_A.lua.bak')
  local idx = Files.delete_log_lines({ ok = false, stage = 'index', name = 'PTAR_A.lua', error = 'Permission denied', removed = {} })
  expect.equal(table.concat(idx, '|'), 'Delete route failed: PTAR_A.lua: the route list could not be updated: Permission denied')
  local file = Files.delete_log_lines({ ok = false, stage = 'file', name = 'PTAR_A.lua', error = 'Permission denied', index_removed = true, removed = {} })
  expect.equal(table.concat(file, '|'), 'Delete route: index entry removed|Delete route failed: PTAR_A.lua: could not delete the file: Permission denied')
  local sib = Files.delete_log_lines({ ok = false, stage = 'sibling', name = 'PTAR_A.lua', failed_file = 'PTAR_A.lua.bak', error = 'Permission denied',
    index_removed = true, removed = { 'PTAR_A.lua' } })
  expect.equal(table.concat(sib, '|'), 'Delete route: index entry removed|Delete route: removed PTAR_A.lua|Delete route failed: PTAR_A.lua: could not remove PTAR_A.lua.bak: Permission denied')
  local bad = Files.delete_log_lines({ ok = false, stage = 'name', name = 'x.txt' })
  expect.equal(table.concat(bad, '|'), 'Delete route failed: x.txt: not a PTAR route file name')
end)
