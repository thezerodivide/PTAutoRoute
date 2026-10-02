-- Requirement tests for PTARNotice (DL-023, developer-approved 2026-10-02): the Group-beta notice is acknowledged once per
-- computer per major.minor version. Real temp directories; failures come from real files, not hooks.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Notice = require 'PTAR.PTARNotice'

local function path(dir) return dir .. '/PTAR_Notice.txt' end
local function write(dir, text)
  local f = assert(io.open(path(dir), 'wb')); f:write(text); f:close()
end
local function text(file)
  local f = io.open(file, 'rb'); if not f then return nil end
  local s = f:read('*a'); f:close(); return s
end
local function shows(dir, version) return (Notice.decide(Notice.read(dir), version)) end

test('DL-023 crit 1: no shared file means the notice shows (first run)', function()
  local dir = T.with_temp_dir()
  local show, reason = Notice.decide(Notice.read(dir), '1.1.0')
  expect.equal(show, true)
  T.assert_contains(reason, 'missing')
end)

test('DL-023 crit 2: saving records the flag and the full version the notice was shown for, in PTAR_Notice.txt', function()
  local dir = T.with_temp_dir()
  expect.equal(Notice.save(dir, '1.1.0-test.23'), true)
  local body = text(path(dir))
  T.assert_contains(body, 'true')
  T.assert_contains(body, '1.1.0-test.23')
end)

test('DL-023 crit 2: after one acknowledgment the notice is hidden for the same version, whichever character reads it', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0')
  expect.equal(shows(dir, '1.1.0'), false)   -- the module takes no character identity: the record is per computer
end)

test('DL-023 crit 3: patch releases and test builds inside an acknowledged major.minor never show it again', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0-test.23')
  for _, v in ipairs({ '1.1.0-test.24', '1.1.0', '1.1.1', '1.1.2-test.4', '1.1.99' }) do
    expect.equal(shows(dir, v), false, v)
  end
end)

test('DL-023 crit 4: a higher minor or major number shows it again', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0')
  expect.equal(shows(dir, '1.2.0'), true)
  expect.equal(shows(dir, '1.2.0-test.1'), true)
  expect.equal(shows(dir, '2.0.0'), true)
end)

test('DL-023 crit 4: major and minor compare as numbers, not text (1.10 is higher than 1.9)', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.9.0')
  expect.equal(shows(dir, '1.10.0'), true)
  local dir2 = T.with_temp_dir()
  Notice.save(dir2, '1.10.0')
  expect.equal(shows(dir2, '1.9.0'), false)   -- and the reverse is a downgrade
end)

test('DL-023 crit 4: dismissing at the new version records it, so the next patch of that version stays quiet', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0')
  expect.equal(shows(dir, '1.2.0'), true)
  Notice.save(dir, '1.2.0')
  expect.equal(shows(dir, '1.2.5'), false)
  expect.equal(shows(dir, '1.3.0'), true)
end)

test('DL-023 downgrade (developer-approved): running a lower major.minor than the one acknowledged does not show it', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.2.0')
  expect.equal(shows(dir, '1.1.5'), false)
  local dir2 = T.with_temp_dir()
  Notice.save(dir2, '2.0.0')
  expect.equal(shows(dir2, '1.9.0'), false)
end)

test('DL-023 crit 6: a malformed shared file counts as not seen and the notice shows, with the reason', function()
  local cases = {
    'garbage\n', '', 'mode_notice_seen=false\nmode_notice_version=1.1.0\n', 'mode_notice_seen=true\n',
    'mode_notice_seen=true\nmode_notice_version=abc\n', 'mode_notice_version=1.1.0\n',
  }
  for i, body in ipairs(cases) do
    local dir = T.with_temp_dir()
    write(dir, body)
    local show, reason = Notice.decide(Notice.read(dir), '1.1.0')
    expect.equal(show, true, 'case ' .. i)
    T.assert_contains(reason, 'malformed')
  end
end)

test('DL-023 crit 6: an unreadable shared file (a directory where the file must be) counts as not seen and shows', function()
  local dir = T.with_temp_dir()
  os.execute('mkdir "' .. path(dir):gsub('/', '\\') .. '"')
  expect.equal(shows(dir, '1.1.0'), true)
end)

test('DL-023 crit 6: a failed save returns the error and leaves the notice showing next run', function()
  local dir = T.with_temp_dir()
  os.execute('mkdir "' .. (path(dir) .. '.tmp'):gsub('/', '\\') .. '"')   -- a directory where the .tmp file must go
  local ok, err = Notice.save(dir, '1.1.0')
  expect.equal(ok, nil)
  expect.equal(type(err), 'string')
  expect.equal(shows(dir, '1.1.0'), true)
end)

test('DL-023 design (atomic save): a second save replaces the record and keeps the previous one as .bak', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0')
  Notice.save(dir, '1.2.0')
  expect.equal(shows(dir, '1.2.3'), false)
  T.assert_contains(text(path(dir) .. '.bak'), '1.1.0')
  expect.equal(text(path(dir) .. '.tmp'), nil)
end)

test('DL-023 crit 8: decide always gives a reason naming the versions it compared', function()
  local dir = T.with_temp_dir()
  Notice.save(dir, '1.1.0-test.23')
  local show, reason = Notice.decide(Notice.read(dir), '1.1.4')
  expect.equal(show, false)
  T.assert_contains(reason, '1.1.0-test.23')
  T.assert_contains(reason, '1.1.4')
  local _, reason2 = Notice.decide(Notice.read(dir), '1.3.0')
  T.assert_contains(reason2, '1.3.0')
end)
