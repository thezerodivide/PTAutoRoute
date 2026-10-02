-- Requirement tests for PTARZoneSelect (DL-021 build 2): the zone-filtered route list, the default, and the
-- zone-change decision. No MacroQuest dependency. Every expectation comes from the approved DL-021 text.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Z = require 'PTAR.PTARZoneSelect'

local function valid(file, name, zone) return { file = file, name = name, zone = zone, incomplete = false,
  label = name .. ' [' .. zone .. '] — ' .. file } end
local function invalid(file, name, zone, err) return { file = file, name = name, zone = zone, error = err,
  label = file .. ' [invalid: ' .. err .. ']' } end
local function files_of(list) local t = {}; for _, e in ipairs(list) do t[#t + 1] = e.file end; return table.concat(t, ',') end

-- ---------------------------------------------------------------- the list
test('DL-021: the list holds only routes whose stored zone matches the current zone', function()
  local entries = { valid('PTAR_A.lua', 'A', 'sleeper'), valid('PTAR_B.lua', 'B', 'eastwastes') }
  expect.equal(files_of(Z.list(entries, 'sleeper', 'full')), 'PTAR_A.lua')
  expect.equal(files_of(Z.list(entries, 'eastwastes', 'compact')), 'PTAR_B.lua')
end)

test('DL-021: full view also lists invalid routes whose readable zone matches; compact lists valid routes only', function()
  local entries = { valid('PTAR_A.lua', 'Alpha', 'sleeper'), invalid('PTAR_X.lua', 'Xray', 'sleeper', 'Bad thing') }
  expect.equal(files_of(Z.list(entries, 'sleeper', 'full')), 'PTAR_A.lua,PTAR_X.lua')
  expect.equal(files_of(Z.list(entries, 'sleeper', 'compact')), 'PTAR_A.lua')
end)

test('DL-021: an invalid route whose zone cannot be read is never listed, in either view', function()
  local entries = { valid('PTAR_A.lua', 'Alpha', 'sleeper'), { file = 'PTAR_Q.lua', error = 'unreadable', label = 'PTAR_Q.lua [invalid: unreadable]' } }
  expect.equal(files_of(Z.list(entries, 'sleeper', 'full')), 'PTAR_A.lua')
  expect.equal(files_of(Z.list(entries, 'sleeper', 'compact')), 'PTAR_A.lua')
end)

test('DL-021: an invalid entry is labeled [INVALID] <name> [<zone>] - <file>, marked not valid, with its reason', function()
  local list = Z.list({ invalid('PTAR_X.lua', 'Xray', 'sleeper', 'Bad thing') }, 'sleeper', 'full')
  expect.equal(list[1].label, '[INVALID] Xray [sleeper] — PTAR_X.lua')
  expect.equal(list[1].valid, false)
  expect.equal(list[1].reason, 'Bad thing')
end)

test('DL-021: an invalid entry with an unreadable route name falls back to the file name in the label', function()
  local e = invalid('PTAR_X.lua', nil, 'sleeper', 'Bad thing')
  local list = Z.list({ e }, 'sleeper', 'full')
  expect.equal(list[1].label, '[INVALID] PTAR_X.lua [sleeper] — PTAR_X.lua')
end)

test('DL-021: a valid entry keeps the existing label and is marked valid', function()
  local list = Z.list({ valid('PTAR_A.lua', 'Alpha', 'sleeper') }, 'sleeper', 'full')
  expect.equal(list[1].label, 'Alpha [sleeper] — PTAR_A.lua')
  expect.equal(list[1].valid, true)
end)

test('DL-021: a route with no endpoint is treated as invalid in full view (with the approved reason), hidden in compact', function()
  local e = valid('PTAR_I.lua', 'Inc', 'sleeper'); e.incomplete = true
  local full = Z.list({ e }, 'sleeper', 'full')
  expect.equal(#full, 1)
  expect.equal(full[1].valid, false)
  expect.equal(full[1].label, '[INVALID] Inc [sleeper] — PTAR_I.lua')
  expect.equal(full[1].reason, 'Route is still being captured; add a Finish or Manual handoff waypoint before running.')
  expect.equal(#Z.list({ e }, 'sleeper', 'compact'), 0)
end)

test('DL-021: the list is sorted by shown name, case-insensitive, with the file name as the tie-breaker (valid and invalid together)', function()
  local entries = { valid('PTAR_3.lua', 'beta', 'z'), valid('PTAR_2.lua', 'alpha', 'z'), valid('PTAR_1.lua', 'Alpha', 'z'),
    invalid('PTAR_4.lua', 'Aardvark', 'z', 'oops') }
  expect.equal(files_of(Z.list(entries, 'z', 'full')), 'PTAR_4.lua,PTAR_1.lua,PTAR_2.lua,PTAR_3.lua')
end)

test('DL-021: the name sort ignores case (a lower-case name sorts before an upper-case one that comes later in the alphabet)', function()
  local entries = { valid('PTAR_1.lua', 'Cherry', 'z'), valid('PTAR_2.lua', 'banana', 'z'), valid('PTAR_3.lua', 'APPLE', 'z') }
  expect.equal(files_of(Z.list(entries, 'z', 'full')), 'PTAR_3.lua,PTAR_2.lua,PTAR_1.lua')
end)

test('DL-021: routes with the same name (ignoring case) are ordered by file name, whatever order they were scanned in', function()
  local entries = { valid('PTAR_C.lua', 'Same', 'z'), valid('PTAR_A.lua', 'SAME', 'z'), valid('PTAR_B.lua', 'same', 'z'),
    valid('PTAR_E.lua', 'Same', 'z'), valid('PTAR_D.lua', 'sAmE', 'z') }
  expect.equal(files_of(Z.list(entries, 'z', 'full')), 'PTAR_A.lua,PTAR_B.lua,PTAR_C.lua,PTAR_D.lua,PTAR_E.lua')
end)

test('DL-021: sorting is by route name, not by file name', function()
  local entries = { valid('PTAR_A.lua', 'Zulu', 'z'), valid('PTAR_B.lua', 'Alpha', 'z') }
  expect.equal(files_of(Z.list(entries, 'z', 'full')), 'PTAR_B.lua,PTAR_A.lua')
end)

-- ---------------------------------------------------------------- the default
test('DL-021: the default is the zone\'s remembered route when it is still a valid route for the zone', function()
  local entries = { valid('PTAR_A.lua', 'Alpha', 'z'), valid('PTAR_B.lua', 'Beta', 'z') }
  expect.equal(Z.default_file(entries, 'z', 'PTAR_B.lua'), 'PTAR_B.lua')
end)

test('DL-021: with no remembered route the default is the first valid route alphabetically', function()
  local entries = { valid('PTAR_B.lua', 'Beta', 'z'), valid('PTAR_A.lua', 'Alpha', 'z') }
  expect.equal(Z.default_file(entries, 'z', nil), 'PTAR_A.lua')
end)

test('DL-021: a remembered route that is gone, invalid, incomplete or now in another zone falls back to the first valid route', function()
  local inc = valid('PTAR_I.lua', 'Inc', 'z'); inc.incomplete = true
  local entries = { valid('PTAR_B.lua', 'Beta', 'z'), valid('PTAR_A.lua', 'Alpha', 'z'), invalid('PTAR_X.lua', 'Xray', 'z', 'bad'),
    inc, valid('PTAR_O.lua', 'Other', 'elsewhere') }
  for _, remembered in ipairs({ 'PTAR_GONE.lua', 'PTAR_X.lua', 'PTAR_I.lua', 'PTAR_O.lua' }) do
    expect.equal(Z.default_file(entries, 'z', remembered), 'PTAR_A.lua', remembered)
  end
end)

test('DL-021: the default never picks an invalid or incomplete route, even when it sorts first', function()
  local inc = valid('PTAR_0.lua', 'Aaa', 'z'); inc.incomplete = true
  local entries = { inc, invalid('PTAR_1.lua', 'Aab', 'z', 'bad'), valid('PTAR_2.lua', 'Zzz', 'z') }
  expect.equal(Z.default_file(entries, 'z', nil), 'PTAR_2.lua')
end)

test('DL-021: a zone with no valid route has no default', function()
  local entries = { invalid('PTAR_1.lua', 'Aab', 'z', 'bad'), valid('PTAR_2.lua', 'Zzz', 'elsewhere') }
  expect.equal(Z.default_file(entries, 'z', nil), nil)
  expect.equal(Z.default_file({}, 'z', 'PTAR_2.lua'), nil)
end)

-- ---------------------------------------------------------------- zone events
test('DL-021: an unknown (nil or empty) zone reading is reported as unavailable, never as a change', function()
  expect.equal(Z.zone_event(nil, 'sleeper'), 'unavailable')
  expect.equal(Z.zone_event('', 'sleeper'), 'unavailable')
end)

test('DL-021: the same zone is no change; a different non-empty zone is a change; the first reading is a change', function()
  expect.equal(Z.zone_event('sleeper', 'sleeper'), 'same')
  expect.equal(Z.zone_event('eastwastes', 'sleeper'), 'changed')
  expect.equal(Z.zone_event('sleeper', nil), 'changed')
end)

-- ---------------------------------------------------------------- what to do about the runner
test('DL-021: Ready or no runner loads the new zone\'s default immediately', function()
  expect.equal(Z.decide('b', nil, nil), 'load_default')
  expect.equal(Z.decide('b', 'Ready', 'a'), 'load_default')
end)

test('DL-021: Completed, Error, Manual handoff and Paused go pending in a zone that is not the loaded route\'s', function()
  for _, status in ipairs({ 'Completed', 'Error', 'Manual handoff', 'Paused' }) do
    expect.equal(Z.decide('b', status, 'a'), 'pending', status)
  end
end)

test('DL-021: returning to the loaded route\'s own stored zone restores it for all four preserved states', function()
  for _, status in ipairs({ 'Completed', 'Error', 'Manual handoff', 'Paused' }) do
    expect.equal(Z.decide('a', status, 'a'), 'restore', status)
  end
end)

test('DL-021: an active run defers the update', function()
  for _, status in ipairs({ 'Running', 'Recovering', 'Waiting for combat', 'Waiting for med break' }) do
    expect.equal(Z.decide('b', status, 'a'), 'defer', status)
    expect.equal(Z.decide('a', status, 'a'), 'defer', status)
  end
end)

-- ---------------------------------------------------------------- the zone-update log line (logging standard)
-- Developer-approved wording (2026-10-02): `Zone update: <action>; zone <zone>; runner <status or none>;
-- loaded <file or none>; displayed <file or none>`.
test('DL-021 logging: the zone-update line has the approved wording and every field', function()
  expect.equal(Z.update_line('pending', 'sleeper', 'Completed', 'PTAR_EW.lua', 'PTAR_Kera.lua'),
    'Zone update: pending; zone sleeper; runner Completed; loaded PTAR_EW.lua; displayed PTAR_Kera.lua')
end)

test('DL-021 logging: a missing runner, loaded file or displayed file is written as "none"', function()
  expect.equal(Z.update_line('clear_runner', 'potimeb', nil, nil, nil),
    'Zone update: clear_runner; zone potimeb; runner none; loaded none; displayed none')
end)

test('DL-021 logging: every action name is passed through unchanged', function()
  for _, action in ipairs({ 'load_default', 'clear_runner', 'pending', 'restore', 'defer' }) do
    expect.truthy(Z.update_line(action, 'z', 'Ready', 'a', 'b'):find('Zone update: ' .. action .. ';', 1, true))
  end
end)
