-- Requirement tests for PTARSettings' new DL-017 fields (mode; seen_mode_notice was removed by DL-023). No MacroQuest dependency, so
-- this uses real temp directories, the same pattern as PTARRouteData's own tests.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Settings = require 'PTAR.PTARSettings'
local BS = package.config:sub(1, 1)

local function identity() return 'TestServer', 'TestChar' end

test('DL-017: a fresh directory with no settings file reads mode as nil (caller applies the Solo default)', function()
  local dir = T.with_temp_dir()
  local settings = Settings.read(dir, identity)
  expect.equal(settings.mode, nil)
end)

test('DL-017: mode="solo" round-trips through save and read', function()
  local dir = T.with_temp_dir()
  local ok = Settings.save(dir, identity, { mode = 'solo' })
  expect.equal(ok, true)
  expect.equal(Settings.read(dir, identity).mode, 'solo')
end)

test('DL-017: mode="group" round-trips through save and read', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { mode = 'group' })
  expect.equal(Settings.read(dir, identity).mode, 'group')
end)

test('DL-017: an invalid mode value on disk is rejected, not trusted as-is (same pattern as door_role)', function()
  local dir = T.with_temp_dir()
  local f = assert(io.open(Settings.path(dir, identity), 'w'))
  f:write('mode=sideways\n')
  f:close()
  expect.equal(Settings.read(dir, identity).mode, nil)
end)

-- DL-023 criterion 5 (developer-approved 2026-10-02): the per-character seen_mode_notice has no effect and is removed from
-- the character's file. These replace the three DL-017 round-trip tests, whose expected values the developer changed.
local function raw_settings(dir, text)
  local f = assert(io.open(Settings.path(dir, identity), 'wb')); f:write(text); f:close()
end
local function file_text(dir)
  local f = assert(io.open(Settings.path(dir, identity), 'rb')); local s = f:read('*a'); f:close(); return s
end

test('DL-023 crit 5: an old seen_mode_notice=true in a character file is ignored on read, and the read says it was found', function()
  local dir = T.with_temp_dir()
  raw_settings(dir, 'mode=group\nseen_mode_notice=true\n')
  local settings = Settings.read(dir, identity)
  expect.equal(settings.seen_mode_notice, nil)
  expect.equal(settings.dropped_notice_flag, true)
  expect.equal(settings.mode, 'group')   -- the rest of the file is still honored
end)

test('DL-023 crit 5: an old seen_mode_notice=false is ignored and reported the same way', function()
  local dir = T.with_temp_dir()
  raw_settings(dir, 'seen_mode_notice=false\n')
  local settings = Settings.read(dir, identity)
  expect.equal(settings.seen_mode_notice, nil)
  expect.equal(settings.dropped_notice_flag, true)
end)

test('DL-023 crit 5: a file without the old key does not report one', function()
  local dir = T.with_temp_dir()
  raw_settings(dir, 'mode=solo\n')
  expect.equal(Settings.read(dir, identity).dropped_notice_flag, nil)
  expect.equal(Settings.read(T.with_temp_dir(), identity).dropped_notice_flag, nil)
end)

test('DL-023 crit 5: saving after reading removes the old key from the character file and keeps everything else', function()
  local dir = T.with_temp_dir()
  raw_settings(dir, 'echo_enabled=true\nmode=group\nseen_mode_notice=true\n')
  local s = Settings.read(dir, identity)
  expect.equal(Settings.save(dir, identity, s), true)
  local text = file_text(dir)
  expect.equal(text:find('seen_mode_notice', 1, true), nil)
  local after = Settings.read(dir, identity)
  expect.equal(after.mode, 'group')
  expect.equal(after.echo_enabled, true)
  expect.equal(after.dropped_notice_flag, nil)
end)

test('DL-023 crit 5: a save never writes seen_mode_notice, even if a caller still passes it', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { mode = 'solo', seen_mode_notice = true })
  expect.equal(file_text(dir):find('seen_mode_notice', 1, true), nil)
  expect.equal(Settings.read(dir, identity).seen_mode_notice, nil)
end)

test('DL-017: mode and door_role are independent -- saving one does not disturb the other (switching modes preserves Group settings)', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { door_role = 'secondary', mode = 'group' })
  Settings.save(dir, identity, { door_role = 'secondary', mode = 'solo' })
  local settings = Settings.read(dir, identity)
  expect.equal(settings.mode, 'solo')
  expect.equal(settings.door_role, 'secondary')   -- untouched by the mode switch
end)

test('DL-017: all settings round-trip together (realistic full save), mirroring actual save_settings() usage', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, {
    last_route = nil, echo_enabled = true, door_role = 'primary',
    mode = 'group',
  })
  local settings = Settings.read(dir, identity)
  expect.equal(settings.echo_enabled, true)
  expect.equal(settings.door_role, 'primary')
  expect.equal(settings.mode, 'group')
end)

test('DL-018 req 9: a fresh directory reads view as nil (caller applies the full-view default)', function()
  local dir = T.with_temp_dir()
  expect.equal(Settings.read(dir, identity).view, nil)
end)

test('DL-018 req 9: view="compact" round-trips through save and read', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { view = 'compact' })
  expect.equal(Settings.read(dir, identity).view, 'compact')
end)

test('DL-018 req 9: view="full" round-trips through save and read', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { view = 'full' })
  expect.equal(Settings.read(dir, identity).view, 'full')
end)

test('DL-018 req 9: an invalid view value on disk is rejected, not trusted as-is', function()
  local dir = T.with_temp_dir()
  local f = assert(io.open(Settings.path(dir, identity), 'w'))
  f:write('view=tiny\n')
  f:close()
  expect.equal(Settings.read(dir, identity).view, nil)
end)

-- DL-021 build 2 (developer-approved supersession, 2026-10-02): the legacy last_route is no longer persisted, so this
-- test no longer expects it to round-trip; it still guards that saving the view leaves the other settings intact.
test('DL-018 req 9/8: saving view leaves the other settings (mode, door_role) intact', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { door_role = 'secondary', mode = 'group', view = 'compact' })
  local s = Settings.read(dir, identity)
  expect.equal(s.view, 'compact'); expect.equal(s.mode, 'group'); expect.equal(s.door_role, 'secondary')
end)

-- ================================================================ DL-021 build 1 (per-zone remembered route)
-- Requirement (developer, 2026-10-02): a route is remembered against its stored starting zone EXACTLY as stored,
-- and nothing may silently skip persistence because of the zone's characters. Storage is one
-- `zone_route=<percent-encoded zone> <file>` line per zone. In build 1 `last_route` is unchanged.
local function zr(zone_routes) return { zone_routes = zone_routes } end

test('DL-021: a fresh directory reads zone_routes as an empty table', function()
  local dir = T.with_temp_dir()
  local s = Settings.read(dir, identity)
  expect.equal(type(s.zone_routes), 'table')
  expect.equal(next(s.zone_routes), nil)
end)

test('DL-021: one remembered route per zone round-trips through save and read', function()
  local dir = T.with_temp_dir()
  expect.equal(Settings.save(dir, identity, zr({ sleeper = 'PTAR_SleepersTombKera.lua', eastwastes = 'PTAR_EW.lua' })), true)
  local s = Settings.read(dir, identity)
  expect.equal(s.zone_routes.sleeper, 'PTAR_SleepersTombKera.lua')
  expect.equal(s.zone_routes.eastwastes, 'PTAR_EW.lua')
end)

test('DL-021: zone strings with spaces, =, %, tabs, newlines and non-ASCII bytes are stored exactly as given', function()
  local dir = T.with_temp_dir()
  local zones = { 'a b', 'x=y', '100%', 'with\ttab', 'two\nlines', 'cr\rlf', 'caf\195\169', '%41', 'plus+and-dash_under', ' lead', 'trail ' }
  local map = {}
  for i, z in ipairs(zones) do map[z] = 'PTAR_R' .. i .. '.lua' end
  expect.equal(Settings.save(dir, identity, zr(map)), true)
  local s = Settings.read(dir, identity)
  for i, z in ipairs(zones) do
    expect.equal(s.zone_routes[z], 'PTAR_R' .. i .. '.lua', 'zone ' .. string.format('%q', z))
  end
end)

test('DL-021: saving again replaces a zone\'s remembered route and leaves other zones alone', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, zr({ sleeper = 'PTAR_A.lua', other = 'PTAR_B.lua' }))
  Settings.save(dir, identity, zr({ sleeper = 'PTAR_C.lua', other = 'PTAR_B.lua' }))
  local s = Settings.read(dir, identity)
  expect.equal(s.zone_routes.sleeper, 'PTAR_C.lua')
  expect.equal(s.zone_routes.other, 'PTAR_B.lua')
end)

test('DL-021: malformed zone_route lines (no file, bad escape, unacceptable file name) are ignored, good ones kept', function()
  local dir = T.with_temp_dir()
  local f = assert(io.open(Settings.path(dir, identity), 'w'))
  f:write('zone_route=nofile\nzone_route=bad%zz PTAR_X.lua\nzone_route=zone ..%2F..%2Fevil.lua\nzone_route=good PTAR_OK.lua\n')
  f:close()
  local s = Settings.read(dir, identity)
  expect.equal(s.zone_routes.good, 'PTAR_OK.lua')
  local n = 0; for _ in pairs(s.zone_routes) do n = n + 1 end
  expect.equal(n, 1)
end)

test('DL-021 build 2: door_role and mode still round-trip beside zone_routes', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { door_role = 'secondary', mode = 'group', zone_routes = { sleeper = 'PTAR_A.lua' } })
  local s = Settings.read(dir, identity)
  expect.equal(s.door_role, 'secondary'); expect.equal(s.mode, 'group')
  expect.equal(s.zone_routes.sleeper, 'PTAR_A.lua')
end)

-- Developer decision, 2026-10-02 (DL-021 open item 8): the legacy single last_route is ignored and removed on the
-- next settings save; it never seeds or influences per-zone defaults. (This supersedes build 1's test that it
-- still round-tripped; build 1 deliberately kept it so startup stayed coherent.)
test('DL-021 build 2: a legacy last_route line in an existing settings file is ignored on read', function()
  local dir = T.with_temp_dir()
  local f = assert(io.open(Settings.path(dir, identity), 'w'))
  f:write('last_route=PTAR_Old.lua\nmode=solo\nzone_route=sleeper PTAR_A.lua\n')
  f:close()
  local s = Settings.read(dir, identity)
  expect.equal(s.last_route, nil)
  expect.equal(s.mode, 'solo')
  expect.equal(s.zone_routes.sleeper, 'PTAR_A.lua')
end)

test('DL-021 build 2: saving never writes last_route, so a legacy value is dropped on the next save', function()
  local dir = T.with_temp_dir()
  local f = assert(io.open(Settings.path(dir, identity), 'w'))
  f:write('last_route=PTAR_Old.lua\nmode=solo\n')
  f:close()
  local s = Settings.read(dir, identity)
  s.last_route = 'PTAR_Old.lua'                     -- even if a caller still hands it back
  Settings.save(dir, identity, s)
  local text = assert(io.open(Settings.path(dir, identity), 'r')):read('*a')
  expect.equal(text:find('last_route', 1, true), nil)
  expect.equal(Settings.read(dir, identity).mode, 'solo')
end)
