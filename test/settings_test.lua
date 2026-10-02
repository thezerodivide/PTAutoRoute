-- Requirement tests for PTARSettings' new DL-017 fields (mode, seen_mode_notice). No MacroQuest dependency, so
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

test('DL-017: seen_mode_notice=true round-trips through save and read', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { seen_mode_notice = true })
  expect.equal(Settings.read(dir, identity).seen_mode_notice, true)
end)

test('DL-017: seen_mode_notice is nil (not false) when never saved, so the modal shows on first run', function()
  local dir = T.with_temp_dir()
  local settings = Settings.read(dir, identity)
  expect.equal(settings.seen_mode_notice, nil)
end)

test('DL-017: seen_mode_notice=false is stored distinctly from never having been set, and still round-trips', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { seen_mode_notice = false })
  expect.equal(Settings.read(dir, identity).seen_mode_notice, false)
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
    mode = 'group', seen_mode_notice = true,
  })
  local settings = Settings.read(dir, identity)
  expect.equal(settings.echo_enabled, true)
  expect.equal(settings.door_role, 'primary')
  expect.equal(settings.mode, 'group')
  expect.equal(settings.seen_mode_notice, true)
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

test('DL-018 req 9/8: saving view leaves the other settings (mode, door_role, last_route) intact', function()
  local dir = T.with_temp_dir()
  Settings.save(dir, identity, { last_route = 'PTAR_X.lua', door_role = 'secondary', mode = 'group', view = 'compact' })
  local s = Settings.read(dir, identity)
  expect.equal(s.view, 'compact'); expect.equal(s.mode, 'group'); expect.equal(s.door_role, 'secondary')
  expect.equal(s.last_route, 'PTAR_X.lua')
end)
