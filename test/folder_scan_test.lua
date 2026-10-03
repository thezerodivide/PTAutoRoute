-- Requirement tests for the route folder scan (DL-024, acceptance criteria approved by the developer 2026-10-02).
-- No MacroQuest dependency: real temp directories, real route files (PTARRouteData's own serializer), and a fake `lfs`
-- modelled on what was observed live (MQClaudeTestBridge DL-022 spikes 11 and 12): lfs.dir returns '.' and '..' with the
-- names, needs its iterator called with the state it returns, and yields nothing for a missing path or a file path;
-- lfs.attributes(path,'mode') is 'directory' only for a directory and nil for an absent path. Failures come from real
-- files (a directory where the index .tmp must go), not test hooks.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Files = require 'PTAR.PTARFiles'
local RD = require 'PTAR.PTARRouteData'

local function normal(id) return { id = id, label = 'L ' .. id, type = 'normal', x = 1, y = 2, z = 3, heading = 90 } end
local function finish(id) local w = normal(id); w.type, w.radius = 'finish', 3; return w end
local function route(name, zone, waypoints)
  return { format_version = 3, next_id = 10, route_name = name, zone_short_name = zone, description = '', waypoints = waypoints }
end
local function write_file(dir, name, text) local f = assert(io.open(dir .. '/' .. name, 'wb')); f:write(text); f:close() end
local function write_route(dir, name, rt) write_file(dir, name, assert(RD.serialize(rt))) end
local function good(dir, name, zone) write_route(dir, name, route('Route ' .. name, zone or 'sleeper', { normal('wp_001'), finish('wp_002') })) end
local function write_index(dir, names) write_file(dir, 'PTAR_Routes.txt', table.concat(names, '\n') .. '\n') end
local function read_all(path) local f = io.open(path, 'rb'); if not f then return nil end; local t = f:read('*a'); f:close(); return t end
local function exists(path) local f = io.open(path, 'rb'); if f then f:close(); return true end; return false end
local function index_lines(dir) return (read_all(dir .. '/PTAR_Routes.txt') or ''):gsub('\r', '') end
local function joined(list) return table.concat(list, ',') end

-- The lister for these tests: the folder's real entries, however the platform spells them. Only the names matter to
-- discover(), which does the filtering itself; real `lfs` listing is covered through make_lister below.
local function lister_of(names) return function() return names end end

-- ---------------------------------------------------------------- criteria 1 and 4: which files are added
test('DL-024 crit 1: a route file in the folder that is not in the index is added and then listed', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua' })
  local r = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(r.status, 'ok')
  expect.equal(joined(r.added), 'PTAR_B.lua')
  expect.equal(index_lines(dir), 'PTAR_A.lua\nPTAR_B.lua\n')
  local listed = {}; for _, e in ipairs(Files.scan(dir)) do listed[#listed + 1] = e.file end
  expect.equal(joined(listed), 'PTAR_A.lua,PTAR_B.lua')
end)

test('DL-024 crit 1: with no index file at all (a new user) every matching file is added and the index is created', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_One.lua'); good(dir, 'PTAR_Two.lua')
  local r = Files.discover(dir, lister_of({ 'PTAR_Two.lua', 'PTAR_One.lua' }))
  expect.equal(r.status, 'ok')
  expect.equal(joined(r.added), 'PTAR_One.lua,PTAR_Two.lua')
  expect.equal(index_lines(dir), 'PTAR_One.lua\nPTAR_Two.lua\n')
end)

test('DL-024 crit 4: names that do not match the PTAR naming rule are never added (.bak, .tmp, other files, bad characters)', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua')
  local junk = { 'PTAR_A.lua.bak', 'PTAR_A.lua.tmp', 'PTAR_Routes.txt', 'PTAR_Routes.txt.bak', 'notes.lua', 'ptar_lower.lua',
    'PTAR_.lua', 'PTAR_has space.lua', 'PTAR_dot.name.lua', 'PTAR_A.LUA', 'desktop.ini', 'PTAR_Settings_s_c.txt' }
  local names = { 'PTAR_A.lua' }
  for _, n in ipairs(junk) do names[#names + 1] = n end
  local r = Files.discover(dir, lister_of(names))
  expect.equal(joined(r.added), 'PTAR_A.lua')
  expect.equal(index_lines(dir), 'PTAR_A.lua\n')
end)

test('DL-024 crit 4: the two legacy SleeperTombRoute names PTARFiles.accept already takes are added too', function()
  local dir = T.with_temp_dir()
  local r = Files.discover(dir, lister_of({ 'SleeperTombRoute.lua', 'SleeperTombRoute_runner_test.lua', 'SleeperTombRoute_other.lua' }))
  expect.equal(joined(r.added), 'SleeperTombRoute.lua,SleeperTombRoute_runner_test.lua')
end)

test('DL-024 crit 4: a file already in the index is not added again, and the matched/already-listed counts are reported', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua' })
  local r = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(r.status, 'ok'); expect.equal(#r.added, 0)
  expect.equal(r.matched, 2); expect.equal(r.listed, 2)
  expect.equal(index_lines(dir), 'PTAR_A.lua\nPTAR_B.lua\n')
end)

test('DL-024 crit 4: nothing new means the index file is not rewritten (no .bak made)', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua')
  write_index(dir, { 'PTAR_A.lua' })
  Files.discover(dir, lister_of({ 'PTAR_A.lua' }))
  expect.equal(exists(dir .. '/PTAR_Routes.txt.bak'), false)
end)

test('DL-024 crit 4: Windows file names ignore case, so a name that differs only in case from an indexed one is the same file and is not added again', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua' })
  local r = Files.discover(dir, lister_of({ 'PTAR_a.lua' }))
  expect.equal(#r.added, 0)
  expect.equal(r.listed, 1)
  expect.equal(index_lines(dir), 'PTAR_A.lua\n')
end)

-- ---------------------------------------------------------------- criterion 5: invalid files are added too (requirement 3)
test('DL-024 req 3 / crit 5: an invalid file and an incomplete file are added, and scan then shows them as invalid or incomplete', function()
  local dir = T.with_temp_dir()
  write_file(dir, 'PTAR_Bad.lua', 'this is not a route')
  write_route(dir, 'PTAR_Inc.lua', route('Unfinished', 'sleeper', { normal('wp_001') }))
  local r = Files.discover(dir, lister_of({ 'PTAR_Bad.lua', 'PTAR_Inc.lua' }))
  expect.equal(joined(r.added), 'PTAR_Bad.lua,PTAR_Inc.lua')
  local by = {}; for _, e in ipairs(Files.scan(dir)) do by[e.file] = e end
  expect.truthy(by['PTAR_Bad.lua'].error ~= nil)
  expect.equal(by['PTAR_Inc.lua'].incomplete, true)
  expect.equal(by['PTAR_Inc.lua'].zone, 'sleeper')
end)

-- ---------------------------------------------------------------- criterion 6: add only
test('DL-024 req 7 / crit 6: existing entries are kept in order, including entries whose files are missing; new names are appended', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_New.lua'); good(dir, 'PTAR_Kept.lua')
  write_index(dir, { 'PTAR_Zzz.lua', 'PTAR_Gone.lua', 'PTAR_Kept.lua' })   -- PTAR_Gone and PTAR_Zzz have no file
  local r = Files.discover(dir, lister_of({ 'PTAR_Kept.lua', 'PTAR_New.lua' }))
  expect.equal(joined(r.added), 'PTAR_New.lua')
  expect.equal(index_lines(dir), 'PTAR_Zzz.lua\nPTAR_Gone.lua\nPTAR_Kept.lua\nPTAR_New.lua\n')
end)

test('DL-024 crit 6: no route file is changed, moved or deleted by a scan', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); write_file(dir, 'PTAR_Bad.lua', 'junk'); write_file(dir, 'PTAR_A.lua.bak', 'bak')
  local before = { a = read_all(dir .. '/PTAR_A.lua'), bad = read_all(dir .. '/PTAR_Bad.lua'), bak = read_all(dir .. '/PTAR_A.lua.bak') }
  Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_Bad.lua', 'PTAR_A.lua.bak' }))
  expect.equal(read_all(dir .. '/PTAR_A.lua'), before.a)
  expect.equal(read_all(dir .. '/PTAR_Bad.lua'), before.bad)
  expect.equal(read_all(dir .. '/PTAR_A.lua.bak'), before.bak)
end)

test('DL-024 crit 6: the index write is atomic like the others: the previous index is kept as .bak and no .tmp is left', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua' })
  Files.discover(dir, lister_of({ 'PTAR_B.lua' }))
  expect.equal((read_all(dir .. '/PTAR_Routes.txt.bak')):gsub('\r', ''), 'PTAR_A.lua\n')
  expect.equal(exists(dir .. '/PTAR_Routes.txt.tmp'), false)
end)

test('DL-024 crit 7 (ordering): added names are in alphabetical order ignoring case, whatever order the folder listing gave', function()
  local dir = T.with_temp_dir()
  local r = Files.discover(dir, lister_of({ 'PTAR_banana.lua', 'PTAR_Cherry.lua', 'PTAR_apple.lua', 'PTAR_Date.lua' }))
  expect.equal(joined(r.added), 'PTAR_apple.lua,PTAR_banana.lua,PTAR_Cherry.lua,PTAR_Date.lua')
end)

-- ---------------------------------------------------------------- criterion 9: a failed write
test('DL-024 req 8 / crit 9: when the index cannot be written the scan reports write_failed with the reason and loses nothing', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua' })
  os.execute('mkdir "' .. (dir .. '/PTAR_Routes.txt.tmp'):gsub('/', '\\') .. '"')   -- a directory where the .tmp file must go
  local r = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(r.status, 'write_failed')
  expect.equal(type(r.error), 'string'); expect.truthy(#r.error > 0)
  expect.equal(#r.added, 0)
  expect.equal(index_lines(dir), 'PTAR_A.lua\n')
  expect.equal(exists(dir .. '/PTAR_B.lua'), true)
end)

test('DL-024 crit 9: after a failed write the next scan adds the files, and a repeated scan never makes a duplicate entry', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua' })
  local blocker = dir .. '/PTAR_Routes.txt.tmp'
  os.execute('mkdir "' .. blocker:gsub('/', '\\') .. '"')
  Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  os.execute('rmdir "' .. blocker:gsub('/', '\\') .. '"')
  local retry = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(retry.status, 'ok'); expect.equal(joined(retry.added), 'PTAR_B.lua')
  local again = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(#again.added, 0)
  expect.equal(index_lines(dir), 'PTAR_A.lua\nPTAR_B.lua\n')
end)

-- ---------------------------------------------------------------- criterion 11: a folder that cannot be listed
test('DL-024 crit 11: a folder that cannot be listed gives status unlistable with the reason and touches nothing', function()
  local dir = T.with_temp_dir()
  write_index(dir, { 'PTAR_A.lua' })
  local r = Files.discover(dir, function() return nil, 'not a directory' end)
  expect.equal(r.status, 'unlistable')
  expect.equal(r.error, 'not a directory')
  expect.equal(#r.added, 0)
  expect.equal(index_lines(dir), 'PTAR_A.lua\n')
  expect.equal(exists(dir .. '/PTAR_Routes.txt.bak'), false)
end)

-- ---------------------------------------------------------------- criterion 10: Delete Route's partial failure
test('DL-024 crit 10 / req 9: a route whose file Delete Route could not delete is added back by the next scan', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua'); good(dir, 'PTAR_B.lua')
  write_index(dir, { 'PTAR_A.lua', 'PTAR_B.lua' })
  local held = assert(io.open(dir .. '/PTAR_A.lua', 'rb'))   -- an open file cannot be deleted on Windows
  local result = Files.delete_route(dir, 'PTAR_A.lua')
  held:close()
  expect.equal(result.stage, 'file')
  expect.equal(index_lines(dir), 'PTAR_B.lua\n')
  local r = Files.discover(dir, lister_of({ 'PTAR_A.lua', 'PTAR_B.lua' }))
  expect.equal(joined(r.added), 'PTAR_A.lua')
  expect.equal(index_lines(dir), 'PTAR_B.lua\nPTAR_A.lua\n')
end)

-- ---------------------------------------------------------------- criterion 7: the added message
test('DL-024 req 6 / crit 7: the added message for one file, two files and exactly three files', function()
  expect.equal(Files.added_message({ 'PTAR_A.lua' }), 'Added 1 route file to the route list: PTAR_A.lua.')
  expect.equal(Files.added_message({ 'PTAR_A.lua', 'PTAR_B.lua' }), 'Added 2 route files to the route list: PTAR_A.lua, PTAR_B.lua.')
  expect.equal(Files.added_message({ 'A.lua', 'B.lua', 'C.lua' }), 'Added 3 route files to the route list: A.lua, B.lua, C.lua.')
end)

test('DL-024 crit 7: a long list shows the first three names then "and N more"', function()
  expect.equal(Files.added_message({ 'A.lua', 'B.lua', 'C.lua', 'D.lua' }), 'Added 4 route files to the route list: A.lua, B.lua, C.lua and 1 more.')
  expect.equal(Files.added_message({ 'A.lua', 'B.lua', 'C.lua', 'D.lua', 'E.lua' }), 'Added 5 route files to the route list: A.lua, B.lua, C.lua and 2 more.')
end)

test('DL-024 req 6: there is no added message when nothing was added', function()
  expect.equal(Files.added_message({}), nil)
end)

-- ---------------------------------------------------------------- requirements 5 and 8: the other approved messages
test('DL-024 req 5: the lfs-missing notice has the approved wording for the Runner and for the Editor', function()
  expect.equal(Files.LFS_MISSING_RUNNER, 'Route folder scan unavailable: LuaFileSystem (lfs) is not installed. New route files will not be found automatically; register them in the Editor.')
  expect.equal(Files.LFS_MISSING_EDITOR, 'Route folder scan unavailable: LuaFileSystem (lfs) is not installed. New route files will not be found automatically; register them with Register Route File...')
end)

test('DL-024 req 8: the write-failure message has the approved wording', function()
  expect.equal(Files.write_failed_message('Permission denied'), 'Could not update the route list: Permission denied. Refresh Routes to try again.')
end)

-- ---------------------------------------------------------------- criterion 12: logging
test('DL-024 crit 12: the scan log lines give the folder, the counts, each added file and that nothing was added', function()
  local lines = Files.discover_log_lines({ status = 'ok', added = { 'PTAR_A.lua', 'PTAR_B.lua' }, matched = 5, listed = 3 }, 'C:/mq/config/PTAR')
  expect.equal(lines[1], 'Route folder scan: C:/mq/config/PTAR: 5 matching files, 3 already listed, 2 added')
  expect.equal(lines[2], 'Route folder scan: added PTAR_A.lua')
  expect.equal(lines[3], 'Route folder scan: added PTAR_B.lua')
  local none = Files.discover_log_lines({ status = 'ok', added = {}, matched = 1, listed = 1 }, 'D')
  expect.equal(none[1], 'Route folder scan: D: 1 matching files, 1 already listed, 0 added')
  expect.equal(#none, 1)
end)

test('DL-024 crit 9/11/12: the log lines for a failed write and an unlistable folder carry the reason and say what happens next', function()
  local w = Files.discover_log_lines({ status = 'write_failed', added = {}, matched = 2, listed = 1, error = 'Permission denied' }, 'D')
  expect.equal(w[#w], 'Route folder scan: could not update the route list: Permission denied; the next scan will try again')
  local u = Files.discover_log_lines({ status = 'unlistable', added = {}, error = 'not a directory' }, 'D')
  expect.equal(u[1], 'Route folder scan: skipped: D could not be listed: not a directory')
end)

-- ---------------------------------------------------------------- make_lister over a fake lfs (observed live behavior)
local function fake_lfs(tree)
  -- tree: { [path] = { 'name', ... } } for directories; anything else is absent or a file (listing yields nothing).
  local lfs = { calls = {} }
  function lfs.attributes(path, what)
    if what == 'mode' then
      if tree[path] then return 'directory' end
      if tree.__files and tree.__files[path] then return 'file' end
      return nil, "cannot obtain information from file '" .. path .. "': No such file or directory", 2
    end
  end
  function lfs.dir(path)
    local names = tree[path]
    local items = names and { '.', '..' } or {}
    for _, n in ipairs(names or {}) do items[#items + 1] = n end
    local handle = { i = 0 }
    local function iter(h)   -- the observed iterator needs the state it was returned with
      assert(h == handle, 'iterator called without its state')
      h.i = h.i + 1
      return items[h.i]
    end
    return iter, handle
  end
  return lfs
end

test('DL-024 / spikes 11-12: make_lister returns the names in a real directory without . and .., using the iterator state', function()
  local lister = Files.make_lister(fake_lfs({ ['D'] = { 'PTAR_A.lua', 'PTAR_B.lua', 'other.txt' } }))
  local names = lister('D')
  expect.equal(joined(names), 'PTAR_A.lua,PTAR_B.lua,other.txt')
end)

test('DL-024 / spike 12: make_lister reports a missing folder and a file path as not listable instead of an empty folder', function()
  local lister = Files.make_lister(fake_lfs({ __files = { ['F'] = true } }))
  local n1, e1 = lister('missing'); expect.equal(n1, nil); expect.truthy(type(e1) == 'string')
  local n2, e2 = lister('F'); expect.equal(n2, nil); expect.truthy(type(e2) == 'string')
end)

test('DL-024: an empty real directory is listable and gives an empty list (not an error)', function()
  local lister = Files.make_lister(fake_lfs({ ['E'] = {} }))
  local names, err = lister('E')
  expect.equal(err, nil); expect.equal(#names, 0)
end)

test('DL-024: make_lister turns an error raised inside lfs into nil plus a message, never a raise', function()
  local lfs = fake_lfs({ ['D'] = { 'a' } })
  lfs.dir = function() error('boom') end
  local names, err = Files.make_lister(lfs)('D')
  expect.equal(names, nil); T.assert_contains(err, 'boom')
end)

test('DL-024 end to end: make_lister over a fake lfs feeding discover adds the matching files only', function()
  local dir = T.with_temp_dir()
  good(dir, 'PTAR_A.lua')
  local lister = Files.make_lister(fake_lfs({ [dir] = { 'PTAR_A.lua', 'PTAR_A.lua.bak', 'notes.txt' } }))
  local r = Files.discover(dir, lister)
  expect.equal(r.status, 'ok'); expect.equal(joined(r.added), 'PTAR_A.lua')
end)
